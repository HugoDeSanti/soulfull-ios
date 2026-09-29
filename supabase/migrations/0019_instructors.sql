-- 0019_instructors.sql
-- Instructor profiles: every guide who teaches in the app gets a page — a
-- photo, a bio, who follows them, whom they follow, and the practices they
-- have published. Five parts:
--
--   1. `instructors` — one row per guide, authored by the team in the
--      dashboard (no client writes), photos in the new public
--      `instructor-photos` bucket.
--   2. Content points at its guide: `practice_sessions.instructor_id` and
--      `programs.instructor_id`, with `lead` kept in step with the guide's
--      name by trigger, so there is one source of truth for it.
--   3. `instructor_follows` — a member following a guide. Owner-scoped RLS,
--      closed to anonymous guests, and no following yourself.
--   4. `instructor_social(id)` — the numbers on the page, and three faces.
--   5. The `instructor-photos` bucket.
--
-- APPLIED 2026-09-28 through the Management API and recorded in
-- supabase_migrations.schema_migrations (0019). Verified live: both client
-- roles hold SELECT on every column but user_id and nothing else on the table;
-- `select=user_id` and `select=*` answer 42501; a guest session reads the
-- guides and the RPC and is refused a follow (42501); a confirmed test member
-- follows (201), a second follow is 23505, unfollow 204, and the counts move;
-- linked to a guide, that member gets following = 1, is_me = true, and is
-- refused following themselves (42501). The test users were deleted.
--
-- Decisions (2026-09-28):
--
--   * A guide is NOT a member account. It is a row the team writes, the way a
--     retreat is. A guide who also has an account is linked through
--     `user_id`, and only that link gives them a "following" count: members
--     follow guides, so what a guide follows is the guides their own account
--     follows. A guide with no account linked follows no one, and says so.
--   * `user_id` never leaves the database. Column grants below leave it out of
--     every client read, so the page cannot be used to find a guide's
--     personal account — and through it their practice history in the feed.
--   * Following is public in the same way the feed is: a follower's face and
--     "Alma G." can appear under "Followed by", friends first. It honours the
--     one switch a member already has for being seen — `share_activity`
--     ("Share my practice", 0015). An opted-out member is COUNTED and never
--     SHOWN. The viewer is never among the faces (the app adds "you" itself).
--   * No minimum below which the count hides (unlike 0018's presence, which
--     hides under 3): a count of followers says nothing about any one person,
--     and a face only appears for someone sharing.

-- ---------------------------------------------------------------------------
-- 1. instructors
-- ---------------------------------------------------------------------------

create table if not exists public.instructors (
    -- A slug ("alma-guerra"): readable in the dashboard, where content is
    -- linked to its guide by hand, and stable once content points at it.
    id          text        primary key
                            check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    name        text        not null check (btrim(name) <> ''),
    -- What they teach, in a few words: "Breathwork · Somatic therapy".
    title       text,
    bio         text,
    -- `bucket/path.jpg`, like every catalog image (ImageSource routes on the
    -- shape). Normally `instructor-photos/<id>.jpg`. Null shows their initial.
    photo_url   text,
    -- Their own member account, when they have one. Server-only; see above.
    user_id     uuid        unique references auth.users (id) on delete set null,
    published   boolean     not null default true,
    sort_order  integer,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

comment on table public.instructors is
    'Guides who teach in the app. Written by the team in the dashboard; read by '
    'everyone (published only). user_id links a guide to their own member account '
    'and is never granted to a client role.';

drop trigger if exists instructors_updated_at on public.instructors;
create trigger instructors_updated_at
    before update on public.instructors
    for each row execute function public.handle_profile_updated_at();

alter table public.instructors enable row level security;

-- Catalog, so both client roles read it (the 0003 trap: an anonymous guest is
-- `authenticated`, not `anon`). Published only. No write policy at all.
drop policy if exists "Published instructors are public" on public.instructors;
create policy "Published instructors are public"
    on public.instructors
    for select
    to anon, authenticated
    using (published);

-- Every column but `user_id`. Supabase's default privileges grant ALL on a
-- new table to both client roles, so the table-level grant has to go before
-- the column-level one means anything — and PostgREST then answers 42501 to a
-- request that names `user_id` (or `*`), which is why the app lists its
-- columns explicitly.
revoke all on public.instructors from anon, authenticated, public;
grant select (id, name, title, bio, photo_url, published, sort_order, created_at, updated_at)
    on public.instructors to anon, authenticated;

create index if not exists instructors_catalog_idx
    on public.instructors (sort_order nulls last, name)
    where published;

-- ---------------------------------------------------------------------------
-- 2. Content points at its guide
-- ---------------------------------------------------------------------------
--
-- `on delete set null`: taking a guide down leaves their practices in the
-- library, credited by the `lead` text they already carry.

alter table public.practice_sessions
    add column if not exists instructor_id text references public.instructors (id) on delete set null;
alter table public.programs
    add column if not exists instructor_id text references public.instructors (id) on delete set null;

create index if not exists practice_sessions_instructor_idx
    on public.practice_sessions (instructor_id) where instructor_id is not null;
create index if not exists programs_instructor_idx
    on public.programs (instructor_id) where instructor_id is not null;

-- `lead` stays — the app, Home's shelf and the payout snapshot
-- (`practice_plays.creator`) all read it — but on a linked row it is a copy of
-- the guide's name, not a second place to type it. Hand-editing `lead` on a
-- linked row is reverted; renaming the guide renames every row.
-- `coalesce` so a bad `instructor_id` fails on the foreign key (a clear
-- error), not on `lead`'s NOT NULL.
create or replace function public.sync_lead_from_instructor()
returns trigger
language plpgsql
as $$
begin
    if new.instructor_id is not null then
        new.lead := coalesce(
            (select i.name from public.instructors i where i.id = new.instructor_id),
            new.lead);
    end if;
    return new;
end;
$$;

drop trigger if exists practice_sessions_sync_lead on public.practice_sessions;
create trigger practice_sessions_sync_lead
    before insert or update of instructor_id, lead on public.practice_sessions
    for each row execute function public.sync_lead_from_instructor();

drop trigger if exists programs_sync_lead on public.programs;
create trigger programs_sync_lead
    before insert or update of instructor_id, lead on public.programs
    for each row execute function public.sync_lead_from_instructor();

create or replace function public.propagate_instructor_name()
returns trigger
language plpgsql
as $$
begin
    if new.name is distinct from old.name then
        update public.practice_sessions set lead = new.name where instructor_id = new.id;
        update public.programs          set lead = new.name where instructor_id = new.id;
    end if;
    return new;
end;
$$;

drop trigger if exists instructors_propagate_name on public.instructors;
create trigger instructors_propagate_name
    after update of name on public.instructors
    for each row execute function public.propagate_instructor_name();

-- ---------------------------------------------------------------------------
-- 3. instructor_follows
-- ---------------------------------------------------------------------------

create table if not exists public.instructor_follows (
    user_id       uuid        not null references auth.users (id) on delete cascade,
    instructor_id text        not null references public.instructors (id) on delete cascade,
    created_at    timestamptz not null default now(),
    primary key (user_id, instructor_id)
);

-- "Who follows this guide, most recent first" — the count and the faces.
create index if not exists instructor_follows_by_instructor_idx
    on public.instructor_follows (instructor_id, created_at desc);

-- The insert policy needs to know whether a guide is published and whether
-- they are the caller — and `user_id` is exactly the column the caller may
-- not read, because a policy runs with the caller's privileges. So the check
-- runs as owner and answers one boolean.
create or replace function public.instructor_is_followable(p_instructor_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.instructors i
        where i.id = p_instructor_id
          and i.published
          and i.user_id is distinct from auth.uid()
    )
$$;

revoke all on function public.instructor_is_followable(text) from public, anon;
grant execute on function public.instructor_is_followable(text) to authenticated;

alter table public.instructor_follows enable row level security;

-- Your own follows only. What others follow is answered in aggregate by
-- `instructor_social()`, never as rows.
drop policy if exists "Members read their own follows" on public.instructor_follows;
create policy "Members read their own follows"
    on public.instructor_follows
    for select
    to authenticated
    using (auth.uid() = user_id);

-- As yourself, as a member (a guest IS `authenticated` — check the claim),
-- a published guide who isn't you.
drop policy if exists "Members follow instructors" on public.instructor_follows;
create policy "Members follow instructors"
    on public.instructor_follows
    for insert
    to authenticated
    with check (
        auth.uid() = user_id
        and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true
        and public.instructor_is_followable(instructor_id)
    );

drop policy if exists "Members unfollow instructors" on public.instructor_follows;
create policy "Members unfollow instructors"
    on public.instructor_follows
    for delete
    to authenticated
    using (auth.uid() = user_id);

-- No update policy: a follow is there or it isn't.
revoke all on public.instructor_follows from anon, public;

-- ---------------------------------------------------------------------------
-- 4. instructor_social(id)
-- ---------------------------------------------------------------------------
--
-- SECURITY DEFINER because it counts across members, which the RLS above
-- exists to prevent — so, like 0018's presence, it answers only aggregates and
-- at most three abbreviated names. Never widen it into a follower list.
--
--   followers       everyone following this guide
--   following       published guides this guide's own account follows (0 with
--                   no account linked)
--   followed_by_me  whether the caller follows them
--   is_me           the caller IS this guide (no Follow button on your own page)
--   faces           up to 3 followers: friends first, then photos, then most
--                   recent; sharing members only; never the caller
--
-- No row for an unpublished or unknown guide.

create or replace function public.instructor_social(p_instructor_id text)
returns table (followers integer, following integer, followed_by_me boolean, is_me boolean, faces jsonb)
language sql
security definer
set search_path = public
stable
as $$
    with target as (
        select i.id, i.user_id
        from public.instructors i
        where i.id = p_instructor_id and i.published
    ),
    my_friends as (
        select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end as id
        from public.friendships f
        where f.status = 'accepted'
          and auth.uid() in (f.requester_id, f.addressee_id)
    )
    select
        (select count(*)::integer
           from public.instructor_follows f
          where f.instructor_id = t.id) as followers,
        case when t.user_id is null then 0 else (
            select count(*)::integer
              from public.instructor_follows f
              join public.instructors i on i.id = f.instructor_id and i.published
             where f.user_id = t.user_id
        ) end as following,
        exists (select 1 from public.instructor_follows f
                 where f.instructor_id = t.id and f.user_id = auth.uid()) as followed_by_me,
        coalesce(t.user_id = auth.uid(), false) as is_me,
        coalesce((
            select jsonb_agg(jsonb_build_object('id', x.id,
                                                'display_name', x.display_name,
                                                'avatar_url', x.avatar_url)
                             order by x.rank)
            from (
                select m.id, m.display_name, m.avatar_url,
                       row_number() over (
                           order by (m.id in (select id from my_friends)) desc,
                                    (m.avatar_url is not null) desc,
                                    f.created_at desc
                       ) as rank
                from public.instructor_follows f
                join public.community_members m on m.id = f.user_id
                join public.profiles p on p.id = f.user_id
                where f.instructor_id = t.id
                  and p.share_activity
                  and f.user_id is distinct from auth.uid()
            ) x
            where x.rank <= 3
        ), '[]'::jsonb) as faces
    from target t
$$;

revoke all on function public.instructor_social(text) from public, anon;
grant execute on function public.instructor_social(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The instructor-photos bucket
-- ---------------------------------------------------------------------------
--
-- Public, like `retreat-images`: a guide's portrait is shown to every guest,
-- so a signed URL buys nothing and expires mid-scroll. The team uploads in the
-- dashboard (which bypasses RLS); no client may write here.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('instructor-photos', 'instructor-photos', true, 2097152, array['image/jpeg', 'image/png'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Instructor photos are publicly readable" on storage.objects;
create policy "Instructor photos are publicly readable"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'instructor-photos');

-- ---------------------------------------------------------------------------
-- Verification (run each on its own — the Management API returns only the
-- last statement's rows)
-- ---------------------------------------------------------------------------
--
--   -- Clients can read every column but user_id:
--   select grantee, column_name from information_schema.column_privileges
--    where table_name = 'instructors' and grantee in ('anon', 'authenticated')
--    order by 1, 2;                                        -- no user_id rows
--   -- …and nothing else on the table (no INSERT/UPDATE/DELETE):
--   select grantee, privilege_type from information_schema.role_table_grants
--    where table_name = 'instructors' and grantee in ('anon', 'authenticated');  -- 0 rows
--
--   -- As a guest session: GET /rest/v1/instructors?select=id,name → 200;
--   --   ?select=user_id → 42501; POST /rest/v1/instructor_follows → 42501;
--   --   POST /rest/v1/rpc/instructor_social {"p_instructor_id": "<id>"} → 200.
--
--   -- As a member: follow → 201; a second follow → 23505 (the app treats it
--   --   as done); follow a guide linked to your own account → 42501; the
--   --   RPC answers followers + 1 and followed_by_me true; unfollow → 204.
--
--   -- lead follows the guide:
--   update public.programs set instructor_id = '<id>' where id = 'finding-ground';
--   select lead from public.programs where id = 'finding-ground';   -- the guide's name
--   update public.instructors set name = name || ' X' where id = '<id>';  -- then check again, and revert
