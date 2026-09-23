-- 0018_presence.sql
-- "75.7k present": how many people are with a practice or a digital retreat
-- right now, and three of their faces.
--
--   1. `practice_presence()` — per practice: the distinct members who STARTED
--      it in the last 24 hours (`practice_plays.started_at`), opened is
--      enough, finishing is not required.
--   2. `program_presence()` — per published program: members enrolled, not
--      finished, and active in it in the last 14 days (joined, finished a
--      day, or started one of its activities). An enrolment abandoned in the
--      spring is not "present".
--
-- Both answer ONLY aggregates. Decisions made with the product owner
-- (2026-09-23), and each is enforced here rather than in the app:
--
--   * Below 3 people a row is not returned at all. "1 present" reads lonely,
--     and a count of one or two beside a face names a person's practice to
--     anyone who can see the row.
--   * Faces are friends first, then members with a photo, most recent first;
--     never the caller (they count, they don't need to see themselves).
--   * Faces honour `share_activity`: an opted-out member is counted, never
--     shown. Guests are never faces (`community_members` is accounts only).
--   * Journal prompts get the count and NO faces — the same privacy line the
--     feed draws (0015), since a prompt's title can say what someone is
--     working through.
--
-- SECURITY DEFINER because they aggregate across members, which RLS on
-- `practice_plays` / `program_enrollments` exists to prevent. That is why the
-- output is limited to the columns above and why nothing but a count and three
-- abbreviated names ever leaves: never widen these into a list of members.
-- Granted to `authenticated` (which includes anonymous guests — browsing is
-- open); `anon` never carries a session in this app.

-- The window read is "started in the last day", by content.
create index if not exists practice_plays_started_idx
    on public.practice_plays (started_at desc, content_kind, content_id)
    where user_id is not null;

-- Programs: members in flight, by program.
create index if not exists program_enrollments_in_flight_idx
    on public.program_enrollments (program_id)
    where completed_at is null;

-- ---------------------------------------------------------------------------
-- 1. Practices
-- ---------------------------------------------------------------------------

create or replace function public.practice_presence()
returns table (content_kind text, content_id integer, present integer, faces jsonb)
language sql
security definer
set search_path = public
stable
as $$
    with recent as (
        select pl.content_kind,
               pl.content_id::integer as content_id,
               pl.user_id,
               max(pl.started_at)     as last_started
        from public.practice_plays pl
        where pl.user_id is not null
          and pl.started_at >= now() - interval '24 hours'
        group by 1, 2, 3
    ),
    counted as (
        select r.content_kind, r.content_id, count(*)::integer as present
        from recent r
        group by 1, 2
        having count(*) >= 3
    ),
    my_friends as (
        select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end as id
        from public.friendships f
        where f.status = 'accepted'
          and auth.uid() in (f.requester_id, f.addressee_id)
    )
    select c.content_kind,
           c.content_id,
           c.present,
           case when c.content_kind = 'journal' then '[]'::jsonb else coalesce((
               select jsonb_agg(jsonb_build_object('id', x.id,
                                                   'display_name', x.display_name,
                                                   'avatar_url', x.avatar_url)
                                order by x.rank)
               from (
                   select m.id, m.display_name, m.avatar_url,
                          row_number() over (
                              order by (m.id in (select id from my_friends)) desc,
                                       (m.avatar_url is not null) desc,
                                       r.last_started desc
                          ) as rank
                   from recent r
                   join public.community_members m on m.id = r.user_id
                   join public.profiles p on p.id = r.user_id
                   where r.content_kind = c.content_kind
                     and r.content_id = c.content_id
                     and p.share_activity
                     and r.user_id is distinct from auth.uid()
               ) x
               where x.rank <= 3
           ), '[]'::jsonb) end as faces
    from counted c
$$;

revoke all on function public.practice_presence() from public, anon;
grant execute on function public.practice_presence() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Digital retreats
-- ---------------------------------------------------------------------------
--
-- "Active in it" compares activity ids as TEXT (`content_id::text =
-- a->>'content_id'`) rather than casting the curriculum's value: the
-- curriculum is hand-authored jsonb, and one malformed id must cost that
-- activity, not throw and blank every program's count.

create or replace function public.program_presence()
returns table (program_id text, present integer, faces jsonb)
language sql
security definer
set search_path = public
stable
as $$
    with in_flight as (
        select e.program_id,
               e.user_id,
               greatest(
                   e.enrolled_at,
                   (select max(d.completed_at)
                      from public.program_day_completions d
                     where d.user_id = e.user_id and d.program_id = e.program_id),
                   (select max(pl.started_at)
                      from public.practice_plays pl
                      -- `pr` is the outer row. A non-array reads as empty
                      -- rather than raising: jsonb_array_elements throws on one.
                      cross join lateral jsonb_array_elements(
                          case jsonb_typeof(pr.curriculum -> 'days')
                              when 'array' then pr.curriculum -> 'days' else '[]'::jsonb end) as day
                      cross join lateral jsonb_array_elements(
                          case jsonb_typeof(day -> 'activities')
                              when 'array' then day -> 'activities' else '[]'::jsonb end) as act
                     where pl.user_id = e.user_id
                       and pl.started_at >= e.enrolled_at
                       and pl.content_kind = act ->> 'kind'
                       and pl.content_id::text = act ->> 'content_id')
               ) as last_active
        from public.program_enrollments e
        join public.programs pr on pr.id = e.program_id and pr.published
        where e.completed_at is null
    ),
    active as (
        select * from in_flight where last_active >= now() - interval '14 days'
    ),
    counted as (
        select a.program_id, count(*)::integer as present
        from active a
        group by 1
        having count(*) >= 3
    ),
    my_friends as (
        select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end as id
        from public.friendships f
        where f.status = 'accepted'
          and auth.uid() in (f.requester_id, f.addressee_id)
    )
    select c.program_id,
           c.present,
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
                                       a.last_active desc
                          ) as rank
                   from active a
                   join public.community_members m on m.id = a.user_id
                   join public.profiles p on p.id = a.user_id
                   where a.program_id = c.program_id
                     and p.share_activity
                     and a.user_id is distinct from auth.uid()
               ) x
               where x.rank <= 3
           ), '[]'::jsonb) as faces
    from counted c
$$;

revoke all on function public.program_presence() from public, anon;
grant execute on function public.program_presence() to authenticated;

-- ---------------------------------------------------------------------------
-- Verification (run each on its own — the Management API returns only the
-- last statement's rows)
-- ---------------------------------------------------------------------------
--
--   -- Both exist, are definer, and only `authenticated` may execute:
--   select p.proname, p.prosecdef,
--          has_function_privilege('anon', p.oid, 'execute')          as anon,
--          has_function_privilege('authenticated', p.oid, 'execute') as authed
--     from pg_proc p where p.proname in ('practice_presence', 'program_presence');
--
--   -- As a guest session: 200, and no row with present < 3.
--   -- As a member with three test members on one practice: one row, present 3,
--   -- two faces (the caller is never among them), and a journal row carries [].
