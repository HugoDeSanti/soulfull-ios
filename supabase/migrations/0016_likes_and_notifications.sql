-- 0016_likes_and_notifications.sql
-- Likes on the Community feed, and the notification a member gets when one
-- of their finished practices is liked.
--
--   1. `practice_play_likes` — one row per (play, liker). A member can like
--      any line they can see in the feed except their own, and unlike it.
--   2. `community_activity` gains `like_count` and `liked_by_me`, so the feed
--      needs no second query and the likes table itself stays owner-scoped.
--   3. `notifications` — written ONLY by a trigger on likes (there is no
--      client insert policy), read and marked-read by the recipient. Unliking
--      removes the notification if it hasn't been read yet, so a mis-tap
--      leaves no ghost. `member_notifications` is the app's read shape.
--
-- Notifications are IN-APP for now: a bell on the Community tab with an
-- unread badge. Push would be a DB webhook on this table → an Edge Function →
-- APNs, and needs an APNs key from the developer portal; nothing here has to
-- change for that, the table is already the source of truth.
--
-- Same lessons as 0015: every owner-rights view is revoked from
-- `authenticated` and granted SELECT back; policy subqueries qualify the
-- outer column (`practice_play_likes.play_id`), because an unqualified
-- `play_id` inside `exists (select … from community_activity ca …)` binds to
-- ca's column and the check becomes a tautology.

-- ---------------------------------------------------------------------------
-- 1. Likes
-- ---------------------------------------------------------------------------

create table if not exists public.practice_play_likes (
    play_id    uuid        not null references public.practice_plays (id) on delete cascade,
    user_id    uuid        not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (play_id, user_id)
);

-- The feed counts per play; the notifications trigger looks up by play too.
create index if not exists practice_play_likes_play_idx on public.practice_play_likes (play_id);

alter table public.practice_play_likes enable row level security;

-- Your own likes, and the likes on your own practices. Counts for everyone
-- else's lines come through the feed view, not through this table.
drop policy if exists "Members read likes that concern them" on public.practice_play_likes;
create policy "Members read likes that concern them"
    on public.practice_play_likes
    for select
    to authenticated
    using (
        auth.uid() = user_id
        or exists (select 1 from public.practice_plays p
                   where p.id = practice_play_likes.play_id and p.user_id = auth.uid())
    );

-- Like a line you can see in the feed, that isn't yours. `community_activity`
-- already encodes "visible": finished, not a journal prompt, not opted out.
drop policy if exists "Members like others' finished practices" on public.practice_play_likes;
create policy "Members like others' finished practices"
    on public.practice_play_likes
    for insert
    to authenticated
    with check (
        auth.uid() = user_id
        and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true
        and exists (select 1 from public.community_activity ca
                    where ca.play_id = practice_play_likes.play_id
                      and ca.user_id <> auth.uid())
    );

drop policy if exists "Members unlike" on public.practice_play_likes;
create policy "Members unlike"
    on public.practice_play_likes
    for delete
    to authenticated
    using (auth.uid() = user_id);

-- No update policy: a like is a fact with a date, not a thing to edit.

-- ---------------------------------------------------------------------------
-- 2. The feed carries its counts
-- ---------------------------------------------------------------------------
--
-- `auth.uid()` inside an owner-rights view still reads the CALLER's JWT — it
-- is a request setting, not a role property — so `liked_by_me` is per viewer.

create or replace view public.community_activity as
select
    pl.id               as play_id,
    pl.user_id,
    m.display_name,
    m.avatar_url,
    pl.content_kind,
    pl.content_id,
    pl.content_title,
    pl.category,
    pl.updated_at       as completed_at,
    (select count(*) from public.practice_play_likes l where l.play_id = pl.id)::integer as like_count,
    exists (select 1 from public.practice_play_likes l
            where l.play_id = pl.id and l.user_id = auth.uid())               as liked_by_me
from public.practice_plays pl
join public.community_members m on m.id = pl.user_id
join public.profiles p on p.id = pl.user_id
where pl.completed
  and pl.content_kind <> 'journal'
  and p.share_activity;

revoke all on public.community_activity from anon, authenticated, public;
grant select on public.community_activity to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Notifications
-- ---------------------------------------------------------------------------

create table if not exists public.notifications (
    id         uuid        primary key default gen_random_uuid(),
    -- The recipient.
    user_id    uuid        not null references auth.users (id) on delete cascade,
    kind       text        not null check (kind in ('like')),
    -- Who did it. Set null if they delete their account: "Someone liked…".
    actor_id   uuid        references auth.users (id) on delete set null,
    play_id    uuid        references public.practice_plays (id) on delete cascade,
    created_at timestamptz not null default now(),
    read_at    timestamptz
);

create index if not exists notifications_recipient_idx
    on public.notifications (user_id, created_at desc);
-- Unliking finds the unread notification it left.
create index if not exists notifications_like_idx
    on public.notifications (actor_id, play_id) where kind = 'like';

alter table public.notifications enable row level security;

drop policy if exists "Members read their own notifications" on public.notifications;
create policy "Members read their own notifications"
    on public.notifications
    for select
    to authenticated
    using (auth.uid() = user_id);

-- Marking read is the only client write. The trigger below freezes everything
-- but `read_at`, so this policy can be plain.
drop policy if exists "Members mark their notifications read" on public.notifications;
create policy "Members mark their notifications read"
    on public.notifications
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Members clear their notifications" on public.notifications;
create policy "Members clear their notifications"
    on public.notifications
    for delete
    to authenticated
    using (auth.uid() = user_id);

-- Deliberately NO insert policy. Rows come from the like trigger, which runs
-- as the table owner.

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
    -- read_at latches: once read, it stays read.
    if old.read_at is not null then
        new.read_at := old.read_at;
    end if;
    return new;
end;
$$;

drop trigger if exists notifications_integrity on public.notifications;
create trigger notifications_integrity
    before update on public.notifications
    for each row execute function public.enforce_notification_integrity();

-- A like on your practice becomes a notification to you. SECURITY DEFINER,
-- owned by the migration's role (the table owner), so it can insert a row the
-- liker could not.
create or replace function public.notify_practice_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    recipient uuid;
begin
    if tg_op = 'INSERT' then
        select p.user_id into recipient from public.practice_plays p where p.id = new.play_id;
        if recipient is not null and recipient <> new.user_id then
            insert into public.notifications (user_id, kind, actor_id, play_id)
            values (recipient, 'like', new.user_id, new.play_id);
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

drop trigger if exists practice_play_likes_notify on public.practice_play_likes;
create trigger practice_play_likes_notify
    after insert or delete on public.practice_play_likes
    for each row execute function public.notify_practice_like();

-- What the app reads: the notification, who did it (abbreviated + avatar,
-- through the owner-rights members view), and the practice it was about.
-- security_invoker, like practice_progress: RLS on `notifications` scopes it
-- to the recipient, and the joined play is the recipient's own, so RLS on
-- `practice_plays` lets it through.
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
left join public.practice_plays pl on pl.id = n.play_id;

revoke all on public.member_notifications from anon, authenticated, public;
grant select on public.member_notifications to authenticated;

-- ---------------------------------------------------------------------------
-- Verification (run after applying, one call each)
--
--   select table_name, grantee, string_agg(privilege_type, ',') from
--     information_schema.role_table_grants
--    where table_name in ('community_activity','member_notifications')
--      and grantee in ('anon','authenticated') group by 1,2;      -- SELECT only
--   select policyname, cmd from pg_policies where tablename in
--     ('practice_play_likes','notifications');                    -- 3 + 3, no insert on notifications
--   -- as member B: like member A's play → A reads one notification, B reads none
--   -- as member A: like own play → 42501; as a guest: like anything → 42501
--   -- as B: unlike → A's unread notification is gone
-- ---------------------------------------------------------------------------
