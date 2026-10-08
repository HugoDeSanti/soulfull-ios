-- 0028_member_safety.sql
-- Member safety for the Community tab — App Store Guideline 1.2 (user-
-- generated content): members must be able to block abusive members and
-- report offensive ones, objectionable material needs a filter, and the
-- people who run the app must be able to act on a report. Six parts:
--
--   1. `member_blocks` — a member blocks another. From then on the two don't
--      exist for each other: neither appears in the other's feed, search,
--      friends, likes, notifications, presence faces or follower faces, and
--      neither can send the other a request or like the other's practice. The
--      block ends any friendship or pending request between them and takes
--      their likes on each other's practices with it. The blocked member is
--      never told, and can never read that they were blocked.
--   2. `community_members` filters blocks both ways. Every social surface
--      reads members through it (the feed joins it, presence and follower
--      faces join it, `member_notifications` joins it, and the friendship and
--      like insert policies check it), so one filter covers all of them.
--      `search_members()` reads `profiles` directly and gets the same filter.
--   3. Names: `community_display_name()` shows "A member" for a name that
--      contains an objectionable word or impersonates the team. A backstop,
--      not the main defence — reports are.
--   4. A 30-day cooldown after a declined friend request. Declining used to
--      delete the row and nothing else, so a stranger could send the same
--      request again the moment it was declined, forever.
--   5. `member_reports` — written only by the `report-member` Edge Function
--      (service role), which also emails the team. No client access at all.
--   6. A like, unliked and liked again within a day, still lands in the
--      bell but no longer buzzes the phone a second time.
--
-- Plus: the avatars bucket stops answering "list every object" to anyone
-- with the anon key (public URLs keep working — a public bucket serves them
-- without a SELECT policy).
--
-- NOT YET APPLIED. Apply through the Management API in one transaction with
-- its schema_migrations row, after a dry run (begin … rollback) with the
-- behaviour checks at the bottom.

-- ---------------------------------------------------------------------------
-- 1. Blocks
-- ---------------------------------------------------------------------------

create table if not exists public.member_blocks (
    blocker_id uuid        not null references auth.users (id) on delete cascade,
    blocked_id uuid        not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    check (blocker_id <> blocked_id)
);

-- `community_members` asks both directions for every row it returns.
create index if not exists member_blocks_blocked_idx
    on public.member_blocks (blocked_id, blocker_id);

alter table public.member_blocks enable row level security;

-- Your own blocks, never the ones against you.
drop policy if exists "Members read their own blocks" on public.member_blocks;
create policy "Members read their own blocks"
    on public.member_blocks
    for select
    to authenticated
    using (auth.uid() = blocker_id);

-- A member blocks a member. A guest can't: a guest is disposable (0023), and a
-- block has to outlive the session that made it. `community_members` is
-- owner-rights, so the existence check sees past the RLS on `profiles` — and
-- it already hides anyone who has blocked the caller, who is invisible to them
-- anyway.
drop policy if exists "Members block members" on public.member_blocks;
create policy "Members block members"
    on public.member_blocks
    for insert
    to authenticated
    with check (
        auth.uid() = blocker_id
        and public.caller_has_account()
        and exists (select 1 from public.community_members m
                    where m.id = member_blocks.blocked_id)
    );

drop policy if exists "Members unblock" on public.member_blocks;
create policy "Members unblock"
    on public.member_blocks
    for delete
    to authenticated
    using (auth.uid() = blocker_id);

-- No update policy: a block is there or it isn't.
revoke all on public.member_blocks from anon, authenticated, public;
grant select, insert, delete on public.member_blocks to authenticated;

-- What a block undoes, in the rows neither side may touch for the other.
-- SECURITY DEFINER: the blocker can't delete the blocked member's like on
-- their own practice, or a notification addressed to someone else.
create or replace function public.apply_member_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    delete from public.friendships f
     where (f.requester_id = new.blocker_id and f.addressee_id = new.blocked_id)
        or (f.requester_id = new.blocked_id and f.addressee_id = new.blocker_id);

    -- Each side's likes on the other's practices. Each delete fires the like
    -- trigger, which takes an unread notification with it.
    delete from public.practice_play_likes l
     using public.practice_plays p
     where p.id = l.play_id
       and ((l.user_id = new.blocked_id and p.user_id = new.blocker_id)
         or (l.user_id = new.blocker_id and p.user_id = new.blocked_id));

    -- …and the read ones, which the like trigger leaves on purpose.
    delete from public.notifications n
     where (n.user_id = new.blocker_id and n.actor_id = new.blocked_id)
        or (n.user_id = new.blocked_id and n.actor_id = new.blocker_id);

    return new;
end;
$$;

drop trigger if exists member_blocks_apply on public.member_blocks;
create trigger member_blocks_apply
    after insert on public.member_blocks
    for each row execute function public.apply_member_block();

-- The You tab's "Blocked members": the people this member has blocked. They
-- are out of `community_members` for the blocker by definition, so the list
-- needs its own read. Only the caller's own blocks; never who blocked them.
create or replace function public.blocked_members()
returns table (id uuid, display_name text, avatar_url text, blocked_at timestamptz)
language sql
security definer
set search_path = public
stable
as $$
    select p.id,
           public.community_display_name(p.full_name) as display_name,
           p.avatar_url,
           b.created_at as blocked_at
    from public.member_blocks b
    join public.profiles p on p.id = b.blocked_id
    where b.blocker_id = auth.uid()
    order by b.created_at desc
$$;

revoke all on function public.blocked_members() from public, anon;
grant execute on function public.blocked_members() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Names (before the views, which call it)
-- ---------------------------------------------------------------------------
--
-- Whole words, case-insensitive, so "Scunthorpe", "Shitara" and "Niggemann"
-- (real names) pass. The list is short on purpose: unambiguous profanity and
-- slurs in English and Spanish, and names that would pass for the team. A
-- false positive costs someone their name in the feed ("A member") until they
-- change it; a false negative is what Report is for.
create or replace function public.is_objectionable_name(full_name text)
returns boolean
language sql
immutable
as $$
    select coalesce(
        lower(full_name) ~ (
            '\m('
            || 'fuck\w*|\w*fucker|shit|shits|shitty|bullshit|cunts?|twats?|wank\w*|'
            || 'whores?|sluts?|bitch\w*|bastards?|assholes?|motherf\w*|'
            || 'nigg(er|ers|a|as|az)|faggots?|fags?|retards?|retarded|kikes?|spics?|chinks?|'
            || 'rapists?|rape|nazis?|hitler|kkk|porn\w*|'
            || 'puta|putas|puto|pendej\w*|cabr[oó]n\w*|mierda|maric[oó]n\w*|verga|coño|'
            || 'soulfull|admin|administrator|moderator'
            || ')\M'
        ),
        false)
$$;

-- "Hugo De Santiago" → "Hugo D.", "Hugo" → "Hugo", '' → "A member", and now
-- an objectionable name → "A member" too. Same signature as 0015, so the
-- views that call it are unaffected.
create or replace function public.community_display_name(full_name text)
returns text
language sql
immutable
as $$
    select case
        when full_name is null or btrim(full_name) = '' then 'A member'
        when public.is_objectionable_name(full_name) then 'A member'
        when array_length(regexp_split_to_array(btrim(full_name), '\s+'), 1) = 1
            then btrim(full_name)
        -- The SECOND word's initial, not the last: "Hugo De Santiago" is
        -- "Hugo D.", the way the person would say it, not "Hugo S.".
        else (regexp_split_to_array(btrim(full_name), '\s+'))[1]
             || ' '
             || left((regexp_split_to_array(btrim(full_name), '\s+'))[2], 1)
             || '.'
    end
$$;

-- ---------------------------------------------------------------------------
-- 2. One filter for every social surface
-- ---------------------------------------------------------------------------
--
-- `auth.uid()` inside an owner-rights view reads the CALLER's JWT (0016), so
-- each member gets their own view of who exists. Same columns as 0015, so
-- `community_activity` (which joins this) needs no change, and neither do
-- `practice_presence()`, `program_presence()` and `instructor_social()`,
-- whose faces join it. Their COUNTS still include everyone — a count names
-- nobody.
create or replace view public.community_members as
select
    p.id,
    public.community_display_name(p.full_name) as display_name,
    p.avatar_url
from public.profiles p
where p.email is not null and p.email <> ''
  and not exists (
      select 1 from public.member_blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = auth.uid())
  );

-- Restated from 0015 (create or replace keeps grants, but this view is the
-- one that was once updatable through — keep the revoke next to it).
revoke all on public.community_members from anon, authenticated, public;
grant select on public.community_members to authenticated;

-- Notifications from someone either side has blocked disappear, rather than
-- turning into "Someone liked…" (the wording kept for a deleted account,
-- whose actor_id is null). Same columns as 0016.
create or replace view public.member_notifications
with (security_invoker = on) as
select
    n.id,
    n.user_id,
    n.kind,
    n.actor_id,
    m.display_name  as actor_name,
    m.avatar_url    as actor_avatar_url,
    n.play_id,
    pl.content_title,
    n.created_at,
    n.read_at
from public.notifications n
left join public.community_members m on m.id = n.actor_id
left join public.practice_plays pl on pl.id = n.play_id
where n.actor_id is null or m.id is not null;

revoke all on public.member_notifications from anon, authenticated, public;
grant select on public.member_notifications to authenticated;

-- 0015's search, with the block filter. It reads `profiles` directly (it
-- matches on the full name, which the view doesn't carry), so it needs the
-- filter of its own.
create or replace function public.search_members(q text)
returns table (id uuid, display_name text, avatar_url text)
language sql
security definer
set search_path = public
stable
as $$
    select p.id,
           public.community_display_name(p.full_name) as display_name,
           p.avatar_url
    from public.profiles p
    where auth.uid() is not null
      and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true
      and length(btrim(q)) >= 2
      and p.id <> auth.uid()
      and p.email is not null and p.email <> ''
      and p.full_name is not null
      and p.full_name ilike '%' || replace(replace(replace(btrim(q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
      and not exists (
          select 1 from public.member_blocks b
          where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
             or (b.blocker_id = p.id and b.blocked_id = auth.uid())
      )
    order by p.full_name
    limit 20
$$;

revoke all on function public.search_members(text) from public, anon;
grant execute on function public.search_members(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Friend requests: a 30-day cooldown after a decline
-- ---------------------------------------------------------------------------
--
-- Decline, withdraw and unfriend are all one DELETE on `friendships` (0015),
-- so a decline is told apart by who deleted what: the ADDRESSEE removing a
-- PENDING row. Only that starts the cooldown, and only for that direction —
-- the person who declined can still send a request the other way.
--
-- The client gets `P0001 friend_request_cooldown` and says so plainly; it
-- learns nothing it didn't already know (its request vanished).

create table if not exists public.friend_request_declines (
    requester_id uuid        not null references auth.users (id) on delete cascade,
    addressee_id uuid        not null references auth.users (id) on delete cascade,
    declined_at  timestamptz not null default now(),
    primary key (requester_id, addressee_id)
);

-- No client access at all: the triggers below are the only readers and
-- writers.
alter table public.friend_request_declines enable row level security;
revoke all on public.friend_request_declines from anon, authenticated, public;

create or replace function public.remember_declined_friend_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if old.status = 'pending' and auth.uid() = old.addressee_id then
        insert into public.friend_request_declines (requester_id, addressee_id, declined_at)
        values (old.requester_id, old.addressee_id, now())
        on conflict (requester_id, addressee_id) do update
            set declined_at = excluded.declined_at;
    end if;
    return old;
end;
$$;

drop trigger if exists friendships_remember_decline on public.friendships;
create trigger friendships_remember_decline
    after delete on public.friendships
    for each row execute function public.remember_declined_friend_request();

create or replace function public.enforce_friend_request_cooldown()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if exists (select 1 from public.friend_request_declines d
               where d.requester_id = new.requester_id
                 and d.addressee_id = new.addressee_id
                 and d.declined_at > now() - interval '30 days') then
        raise exception 'friend_request_cooldown'
            using errcode = 'P0001',
                  hint = 'A declined request can be sent again 30 days after it was declined.';
    end if;
    return new;
end;
$$;

drop trigger if exists friendships_cooldown on public.friendships;
create trigger friendships_cooldown
    before insert on public.friendships
    for each row execute function public.enforce_friend_request_cooldown();

-- ---------------------------------------------------------------------------
-- 5. Reports
-- ---------------------------------------------------------------------------
--
-- One row per report, written by `report-member` with the service role, which
-- also emails the team (docs/MODERATION.md is the runbook). The snapshot
-- columns keep what was reported readable after the member changes it or
-- deletes their account. A guest may report (safety isn't gated); their
-- reporter_id goes null when the guest is purged.

create table if not exists public.member_reports (
    id                  uuid        primary key default gen_random_uuid(),
    reporter_id         uuid        references auth.users (id) on delete set null,
    reported_id         uuid        references auth.users (id) on delete set null,
    play_id             uuid        references public.practice_plays (id) on delete set null,
    reason              text        not null
                                    check (reason in ('photo', 'name', 'harassment', 'spam', 'other')),
    details             text        check (details is null or char_length(details) <= 1000),
    -- What the reported member looked like when reported.
    reported_name       text,
    reported_avatar_url text,
    content_title       text,
    status              text        not null default 'open'
                                    check (status in ('open', 'actioned', 'dismissed')),
    resolution          text,
    created_at          timestamptz not null default now(),
    resolved_at         timestamptz
);

create index if not exists member_reports_open_idx
    on public.member_reports (status, created_at desc);
-- The function's per-reporter rate limit.
create index if not exists member_reports_reporter_idx
    on public.member_reports (reporter_id, created_at desc);

alter table public.member_reports enable row level security;
revoke all on public.member_reports from anon, authenticated, public;

-- ---------------------------------------------------------------------------
-- 6. One buzz per like
-- ---------------------------------------------------------------------------
--
-- Like → unlike → like used to push every time: the unlike removes the unread
-- notification (0016, on purpose), and the next like makes a new one, which
-- 0017 pushes. Now a like from the same person on the same practice within a
-- day of the last one that pushed is `silent`: it still lands in the bell,
-- and the push trigger skips it.

alter table public.notifications add column if not exists silent boolean not null default false;

create table if not exists public.like_echoes (
    actor_id    uuid        not null references auth.users (id) on delete cascade,
    play_id     uuid        not null references public.practice_plays (id) on delete cascade,
    notified_at timestamptz not null default now(),
    primary key (actor_id, play_id)
);

alter table public.like_echoes enable row level security;
revoke all on public.like_echoes from anon, authenticated, public;

create or replace function public.notify_practice_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    recipient     uuid;
    last_notified timestamptz;
    quiet         boolean;
begin
    if tg_op = 'INSERT' then
        select p.user_id into recipient from public.practice_plays p where p.id = new.play_id;
        if recipient is not null and recipient <> new.user_id then
            select e.notified_at into last_notified
              from public.like_echoes e
             where e.actor_id = new.user_id and e.play_id = new.play_id;
            quiet := coalesce(last_notified > now() - interval '24 hours', false);
            insert into public.notifications (user_id, kind, actor_id, play_id, silent)
            values (recipient, 'like', new.user_id, new.play_id, quiet);
            if not quiet then
                insert into public.like_echoes (actor_id, play_id, notified_at)
                values (new.user_id, new.play_id, now())
                on conflict (actor_id, play_id) do update set notified_at = excluded.notified_at;
            end if;
        end if;
        return new;
    else
        -- A retracted like takes its unread notification with it. A read one
        -- stays: they already saw it, and a vanishing history is confusing.
        delete from public.notifications
         where kind = 'like' and actor_id = old.user_id and play_id = old.play_id
           and read_at is null;
        return old;
    end if;
end;
$$;

-- 0016's integrity trigger, freezing `silent` with the rest.
create or replace function public.enforce_notification_integrity()
returns trigger
language plpgsql
as $$
begin
    new.id         := old.id;
    new.user_id    := old.user_id;
    new.kind       := old.kind;
    new.actor_id   := old.actor_id;
    new.play_id    := old.play_id;
    new.created_at := old.created_at;
    new.silent     := old.silent;
    -- read_at latches: once read, it stays read.
    if old.read_at is not null then
        new.read_at := old.read_at;
    end if;
    return new;
end;
$$;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push
    after insert on public.notifications
    for each row
    when (not new.silent)
    execute function public.push_notification();

-- ---------------------------------------------------------------------------
-- 7. Avatars: no listing
-- ---------------------------------------------------------------------------
--
-- 0015 let `anon` and `authenticated` SELECT every object in `avatars`, which
-- with the anon key in the app binary meant anyone could list every member's
-- id that has a photo. A public bucket serves `/object/public/…` URLs without
-- any SELECT policy, so the faces keep loading. A member keeps SELECT on their
-- own folder, which Storage needs to delete an old photo.
drop policy if exists "Avatars are publicly readable" on storage.objects;
drop policy if exists "Members read their own avatar folder" on storage.objects;
create policy "Members read their own avatar folder"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- Verification (each on its own — the Management API returns only the last
-- statement's rows)
-- ---------------------------------------------------------------------------
--
--   -- grants: SELECT only on the views; nothing at all on the four new
--   -- server-only tables; select/insert/delete on member_blocks
--   select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type)
--     from information_schema.role_table_grants
--    where table_name in ('community_members', 'member_notifications', 'member_blocks',
--                         'member_reports', 'friend_request_declines', 'like_echoes')
--      and grantee in ('anon', 'authenticated') group by 1, 2;
--
--   select public.community_display_name('Hugo De Santiago');   -- Hugo D.
--   select public.community_display_name('Shitara Kenji');      -- Shitara K.
--   select public.community_display_name('Big Shit');           -- A member
--   select public.community_display_name('Soulfull Team');      -- A member
--
--   -- As members A and B (set_config request.jwt.claims + set local role
--   -- authenticated, inside begin … rollback):
--   --   B sends A a request; A deletes it (decline) → B sends again: P0001
--   --     friend_request_cooldown; A can still send B a request.
--   --   B withdraws their own request → B can send again (no cooldown).
--   --   A and B are friends, B liked A's play → A blocks B: the friendship,
--   --     the like and its notification are gone; A's community_members has
--   --     no B, B's has no A; B's search for A's name is empty; B's like on
--   --     A's play → 42501; B's request to A → 42501; B cannot read A's
--   --     member_blocks row; blocked_members() as A lists B.
--   --   A guest inserting into member_blocks → 42501.
--   --   B likes A's play, unlikes, likes again → two notifications over the
--   --     day, the second silent = true.
