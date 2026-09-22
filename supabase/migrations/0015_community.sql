-- 0015_community.sql
-- The Community tab: what everyone (or just your friends) has practised lately,
-- with a face beside each line. Four parts:
--
--   1. `profiles` grows `avatar_url` (a path in the new public `avatars`
--      bucket) and `share_activity` (an opt-out from the feed).
--   2. Two OWNER-RIGHTS views punch a deliberate, narrow hole through the
--      owner-only RLS on `profiles` and `practice_plays`: `community_members`
--      (id, abbreviated name, avatar) and `community_activity` (finished
--      practices, joined to the member who finished them).
--   3. `friendships` — a request from one member to another, accepted or
--      pending — with owner-scoped RLS, closed to anonymous guests.
--   4. `search_members(q)` — find a member by name to send a request to.
--
-- APPLIED to the live project 2026-09-22 through the Management API and
-- recorded in supabase_migrations.schema_migrations (0015). Two corrections
-- were applied the same day and are folded in below: the abbreviation takes
-- the second word's initial, and the view revoke names `authenticated`.
-- Verified as an anonymous guest (reads 200, every write 42501) and as two
-- confirmed test members (search, request, accept, the trigger holding
-- `accepted`, the avatar shape constraint, the pair uniqueness).
--
-- What leaves the row, and what doesn't. Every other reader of `profiles` is
-- its owner. These views show OTHER members exactly three things: the id, the
-- name as "Hugo D." (first name + last initial — `community_display_name`
-- abbreviates in SQL, so the full name never crosses the wire), and the avatar
-- path. Email, onboarding answers and the Stripe id stay behind RLS. The feed
-- exposes a finished practice's title, kind and category, and when — never
-- seconds played, never anything unfinished, and NEVER a journal prompt:
-- reflections are promised private, and "Hugo D. practised 'What are you
-- afraid of?'" gives away the subject even though the writing stays on the
-- phone. Guests (anonymous sessions) appear in neither view — they have no
-- name, and nothing of theirs is ever shown.

-- ---------------------------------------------------------------------------
-- 1. profiles: a face, and a say in whether you appear
-- ---------------------------------------------------------------------------

alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists share_activity boolean not null default true;

-- The owner can write avatar_url (the existing update policy covers every
-- column), so bound what it can hold: only a path in THIS member's own folder
-- of the avatars bucket. Without this a member could point their avatar at any
-- https URL — an image hosted anywhere, shown to every other member through
-- ImageSource's direct-URL route, and a tracking pixel fired from every
-- member's phone that scrolls past it.
alter table public.profiles drop constraint if exists profiles_avatar_url_shape;
alter table public.profiles add constraint profiles_avatar_url_shape check (
    avatar_url is null
    or avatar_url ~ ('^avatars/' || id::text || '/[0-9a-f-]{36}\.jpg$')
);

comment on column public.profiles.avatar_url is
    'Storage path of the profile photo, bucket first ("avatars/<user id>/<uuid>.jpg"), '
    'rendered by ImageSource/CatalogImage. A new upload gets a new uuid so caches '
    'never serve the old face; the app deletes the previous object best-effort.';

comment on column public.profiles.share_activity is
    'False hides this member''s finished practices from community_activity. '
    'They stay findable as a friend. Toggled on the You tab.';

-- "Hugo De Santiago" → "Hugo D.", "Hugo" → "Hugo", '' → "A member".
-- IMMUTABLE so it can sit in a view and an index without surprises.
create or replace function public.community_display_name(full_name text)
returns text
language sql
immutable
as $$
    select case
        when full_name is null or btrim(full_name) = '' then 'A member'
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
-- 2. The two owner-rights views
-- ---------------------------------------------------------------------------
--
-- ⚠️ These are deliberately NOT `security_invoker`. `practice_progress` is,
-- because it must show a member only their own rows. These must show a member
-- OTHER people's rows, so they run as their owner and bypass RLS — the same
-- shape as `practice_creator_earnings`, but granted to clients on purpose.
-- Which is exactly why the column list is short and every column is named:
-- `select *` here would be a leak waiting for the next `alter table`.

-- A member is a permanent account. Guests have no email (0009 mirrors
-- auth.users.email into profiles.email; an anonymous session has none) and no
-- name to show, so they are simply absent.
create or replace view public.community_members as
select
    p.id,
    public.community_display_name(p.full_name) as display_name,
    p.avatar_url
from public.profiles p
where p.email is not null and p.email <> '';

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
    -- The ledger heartbeats until the practice ends, so the row's last write
    -- is (to within one heartbeat) the moment it was finished.
    pl.updated_at       as completed_at
from public.practice_plays pl
join public.community_members m on m.id = pl.user_id
join public.profiles p on p.id = pl.user_id
where pl.completed
  and pl.content_kind <> 'journal'
  and p.share_activity;

-- `authenticated` only, and SELECT only. Anonymous guests ARE `authenticated`
-- (0003's trap), so they can read the feed — browsing is open, and a feed is
-- browsing. The `anon` role never carries a session in this app; keep it out.
--
-- ⚠️ The revoke must name `authenticated` too. Supabase's default privileges
-- grant ALL on a new view to `authenticated`, and `community_members` is a
-- simple enough view to be auto-updatable — with owner rights. Left in place,
-- a member could `update community_members set avatar_url = …` on ANY row and
-- walk straight past the RLS on `profiles`. Caught on the live project
-- 2026-09-22 (the first version revoked from `anon, public` only).
revoke all on public.community_members  from anon, authenticated, public;
revoke all on public.community_activity from anon, authenticated, public;
grant select on public.community_members  to authenticated;
grant select on public.community_activity to authenticated;

-- The feed reads "finished, newest first" and "finished by these people".
create index if not exists practice_plays_completed_recent_idx
    on public.practice_plays (updated_at desc)
    where completed;
create index if not exists practice_plays_completed_by_member_idx
    on public.practice_plays (user_id, updated_at desc)
    where completed;

-- ---------------------------------------------------------------------------
-- 3. friendships
-- ---------------------------------------------------------------------------
--
-- One row per request, from `requester_id` to `addressee_id`. `pending` until
-- the addressee accepts; either side can delete it at any point (decline,
-- withdraw, or unfriend — one verb in the table, three in the UI). A pair can
-- have only one row whichever way round it was sent.

create table if not exists public.friendships (
    requester_id uuid        not null references auth.users (id) on delete cascade,
    addressee_id uuid        not null references auth.users (id) on delete cascade,
    status       text        not null default 'pending'
                             check (status in ('pending', 'accepted')),
    created_at   timestamptz not null default now(),
    responded_at timestamptz,
    primary key (requester_id, addressee_id),
    check (requester_id <> addressee_id)
);

create unique index if not exists friendships_pair_idx
    on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

-- Each side lists "mine" from its own column.
create index if not exists friendships_addressee_idx
    on public.friendships (addressee_id, status);

-- The only legal update is pending → accepted. Identity and the request date
-- are frozen; the response date is stamped by the server, not sent.
create or replace function public.enforce_friendship_integrity()
returns trigger
language plpgsql
as $$
begin
    if tg_op = 'UPDATE' then
        new.requester_id := old.requester_id;
        new.addressee_id := old.addressee_id;
        new.created_at   := old.created_at;
        if old.status = 'accepted' then
            new.status := 'accepted';
            new.responded_at := old.responded_at;
        elsif new.status = 'accepted' then
            new.responded_at := now();
        else
            new.responded_at := old.responded_at;
        end if;
    else
        new.status := 'pending';
        new.responded_at := null;
    end if;
    return new;
end;
$$;

drop trigger if exists friendships_integrity on public.friendships;
create trigger friendships_integrity
    before insert or update on public.friendships
    for each row execute function public.enforce_friendship_integrity();

alter table public.friendships enable row level security;

-- Same shape as 0013: `to authenticated`, and the anonymous claim checked
-- explicitly because a guest IS `authenticated`.
drop policy if exists "Members read their own friendships" on public.friendships;
create policy "Members read their own friendships"
    on public.friendships
    for select
    to authenticated
    using (auth.uid() in (requester_id, addressee_id));

-- A request goes from me, to a real member. `community_members` is
-- owner-rights, so the existence check works from inside a policy where a
-- direct read of `profiles` would see nothing but my own row.
drop policy if exists "Members send friend requests" on public.friendships;
create policy "Members send friend requests"
    on public.friendships
    for insert
    to authenticated
    with check (
        auth.uid() = requester_id
        and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true
        and exists (select 1 from public.community_members m where m.id = addressee_id)
    );

-- Only the person asked can accept, and accepting is the only change allowed
-- (the trigger makes anything else a no-op).
drop policy if exists "Addressees accept friend requests" on public.friendships;
create policy "Addressees accept friend requests"
    on public.friendships
    for update
    to authenticated
    using (auth.uid() = addressee_id and status = 'pending')
    with check (auth.uid() = addressee_id and status = 'accepted');

drop policy if exists "Members end friendships" on public.friendships;
create policy "Members end friendships"
    on public.friendships
    for delete
    to authenticated
    using (auth.uid() in (requester_id, addressee_id));

-- ---------------------------------------------------------------------------
-- 4. Finding someone
-- ---------------------------------------------------------------------------
--
-- Search is by NAME, over `full_name`, and answers with the abbreviated name —
-- so "De Santiago" finds Hugo without the surname ever being returned. Never by
-- email: an "is this address a member?" oracle is exactly the enumeration
-- AccountViewModel goes out of its way to avoid. Members only, two characters
-- minimum, twenty results, never yourself.
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
    order by p.full_name
    limit 20
$$;

revoke all on function public.search_members(text) from public, anon;
grant execute on function public.search_members(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The avatars bucket
-- ---------------------------------------------------------------------------
--
-- Public, like `retreat-images`, and for the same reason: a face in a feed is
-- shown to every member, so a signed URL buys nothing and expires mid-scroll.
-- Small (the app downsizes to 512px JPEG before upload; 1MB is generous).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Avatars are publicly readable" on storage.objects;
create policy "Avatars are publicly readable"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'avatars');

-- A member writes only inside their own folder: `avatars/<user id>/…`. That
-- folder is what the profiles check constraint above ties avatar_url to, so
-- the two agree about whose photo a path can be.
drop policy if exists "Members upload their own avatar" on storage.objects;
create policy "Members upload their own avatar"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true
  );

drop policy if exists "Members replace their own avatar" on storage.objects;
create policy "Members replace their own avatar"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Members remove their own avatar" on storage.objects;
create policy "Members remove their own avatar"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- Verification (run after applying)
--
--   -- the views exist and answer as a member (200 + rows) — and note that a
--   -- guest session ALSO reads them, by design
--   select * from public.community_members limit 3;
--   select * from public.community_activity order by completed_at desc limit 3;
--
--   -- both views run as owner (security_invoker absent / false)
--   select c.relname, c.reloptions from pg_class c
--    where c.relname in ('community_members', 'community_activity');
--
--   -- friendships: 4 policies, all `to authenticated`
--   select policyname, cmd, roles from pg_policies where tablename = 'friendships';
--
--   -- an anonymous guest inserting a request is refused (42501)
--   -- a member cannot PATCH a row they requested (0 rows) — only the addressee can
--   -- an update setting status back to 'pending' leaves it 'accepted' (trigger)
--
--   -- the avatar shape constraint rejects an outside URL
--   update public.profiles set avatar_url = 'https://example.com/x.jpg' where id = auth.uid();  -- 23514
-- ---------------------------------------------------------------------------
