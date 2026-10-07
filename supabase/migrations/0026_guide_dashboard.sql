-- 0026_guide_dashboard.sql
-- A guide's own numbers, for the dashboard on their You tab: how many people
-- practised with them, what they earned in past months, and what they are
-- earning this month. Four parts:
--
--   1. `practice_plays.instructor_id`: the guide a play credits, stamped by
--      the server when the row is inserted and frozen after that.
--   2. `creator_pools`: the amount the team sets aside for guides each month.
--   3. `creator_pool_shares`: each guide's share of each month's pool, by
--      minutes heard. Owner-rights and service-only, like
--      `practice_creator_earnings` (0008).
--   4. `guide_dashboard()`: the caller's own numbers, if the team has linked
--      their account to a guide (`instructors.user_id`, 0019).
--
-- The rule (the owner's decision, 2026-10-07): a guide earns on TIME HEARD
-- and is paid a SHARE OF A MONTHLY POOL. The team enters each month's pool.
-- A guide's share is their sessions' seconds heard that month over every
-- guide's, so the payout run and the dashboard read one view and can't
-- disagree. While a month is running, the figure is an estimate from the share
-- so far, and a month with no pool entered yet shows minutes and share but no
-- amount. Nothing is ever estimated from a pool that hasn't been set.
--
-- What counts:
--   * Sessions only (`content_kind = 'session'`), the media `PlaybackReporter`
--     measures. The written libraries are display-only for payouts
--     (`creditsCreator` in Swift). Their plays are stamped too, so a guide sees
--     who opened their movement sequences and recipes, but they never enter
--     a share.
--   * A guide's own plays never count, toward their share or their audience.
--   * Plays by members who have since deleted their account still count (the
--     row is anonymised, not deleted; see 0008). They drop out of "people",
--     which counts accounts.
--   * Months run on UTC, so a play has one month wherever it was heard.
--
-- Decisions (2026-10-07):
--
--   * `instructor_id` is a SNAPSHOT with no foreign key, like `creator`. A
--     foreign key would need `on delete set null` or `restrict`. The first
--     is an UPDATE, which the freeze below reverts (the trap 0008 documents
--     for `user_id`), and the second would stop the team taking a guide down
--     once anyone had heard them. As a snapshot, a guide who is removed keeps
--     the minutes they earned.
--   * It is set by the server from the content row, never by the client.
--     `creator` is a name the client sends, so a modified client could put
--     any name there. `instructor_id` comes from `practice_sessions` (or the
--     written tables), so payouts no longer depend on anything the phone says
--     about whose practice it was.
--   * Earnings are rounded DOWN to the cent, so the shares of a pool never
--     add up to more than the pool.
--
-- APPLIED 2026-10-07 through the Management API, in one transaction with its
-- supabase_migrations.schema_migrations row (0026), after a dry run inside an
-- aborted transaction. The dry run, as two throwaway confirmed members (a guide
-- linked to alma-guerra and a listener) on a session given that guide: a play
-- inserted claiming another guide was stamped alma-guerra; a PATCH to
-- instructor_id and seconds_played = 99999 left the guide and clamped to 900;
-- the guide's own 300s play didn't count (their month: 900s, a 100% share, the
-- whole $1,000 test pool); the listener and a guest claim got no row; both
-- client tables answered 42501; deleting the listener nulled user_id and kept
-- instructor_id. Verified live after applying: no client grants on either
-- table, EXECUTE for `authenticated` only, both triggers enabled, no
-- updated_at moved by the backfill (max unchanged), the backfill credited the
-- 6 written-practice plays to their guides and no session play (no session
-- had a guide), and over REST the anon key gets 42501 from the function and
-- both tables (present, refused).

-- ---------------------------------------------------------------------------
-- 1. practice_plays.instructor_id
-- ---------------------------------------------------------------------------

alter table public.practice_plays
    add column if not exists instructor_id text;

comment on column public.practice_plays.instructor_id is
    'The guide this play credits: a snapshot of the content row''s instructor_id, '
    'set by trigger at insert and frozen after it. No foreign key, on purpose (0026). '
    'Payouts count content_kind = ''session'' only.';

-- The dashboard and the payout view both read a guide's plays by month.
create index if not exists practice_plays_instructor_idx
    on public.practice_plays (instructor_id, created_at)
    where instructor_id is not null;

-- Backfill, BEFORE the stamping trigger exists (its freeze would revert these
-- updates), and with the integrity trigger off. That trigger sets
-- `updated_at = now()` on every update, and `practice_progress` reads
-- `max(updated_at)` as `last_played_at`: moving it would reorder every
-- member's Continue card, and it would make old completions count toward
-- program days that are open now (a day's completion latches, so that can't
-- be undone). This touches `instructor_id` and nothing else.
--
-- A session play is credited only when the session's guide is still the
-- creator the play was snapshotted with. A play made under another name
-- (reassigned or renamed since) stays uncredited rather than paying whoever
-- holds the session now. The written libraries never had a creator, so their
-- plays take the row's guide as it is.

alter table public.practice_plays disable trigger practice_plays_integrity;

update public.practice_plays p
   set instructor_id = s.instructor_id
  from public.practice_sessions s
  join public.instructors i on i.id = s.instructor_id
 where p.content_kind = 'session'
   and p.content_id = s.id
   and p.instructor_id is null
   and p.creator = i.name;

update public.practice_plays p
   set instructor_id = t.instructor_id
  from public.journal_prompts t
 where p.content_kind = 'journal' and p.content_id = t.id
   and t.instructor_id is not null and p.instructor_id is null;

update public.practice_plays p
   set instructor_id = t.instructor_id
  from public.exercises t
 where p.content_kind = 'exercise' and p.content_id = t.id
   and t.instructor_id is not null and p.instructor_id is null;

update public.practice_plays p
   set instructor_id = t.instructor_id
  from public.recipes t
 where p.content_kind = 'recipe' and p.content_id = t.id
   and t.instructor_id is not null and p.instructor_id is null;

alter table public.practice_plays enable trigger practice_plays_integrity;

-- SECURITY DEFINER so the lookup sees the content row whatever the caller may
-- read (a program-only session, an unpublished practice). It reads one column
-- and returns nothing to the caller.
create or replace function public.stamp_practice_play_instructor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if tg_op = 'INSERT' then
        -- Whatever the client sent is overwritten: it has no say in who is paid.
        new.instructor_id := case new.content_kind
            when 'session'  then (select s.instructor_id from public.practice_sessions s where s.id = new.content_id)
            when 'journal'  then (select t.instructor_id from public.journal_prompts   t where t.id = new.content_id)
            when 'exercise' then (select t.instructor_id from public.exercises         t where t.id = new.content_id)
            when 'recipe'   then (select t.instructor_id from public.recipes           t where t.id = new.content_id)
        end;
    else
        -- Frozen, unconditionally. There is no foreign key whose ON DELETE
        -- action could need to change it (see the decisions above), and a
        -- null left open would let a client credit an uncredited play to any
        -- guide it liked.
        new.instructor_id := old.instructor_id;
    end if;
    return new;
end;
$$;

revoke all on function public.stamp_practice_play_instructor() from public, anon, authenticated;

drop trigger if exists practice_plays_stamp_instructor on public.practice_plays;
create trigger practice_plays_stamp_instructor
    before insert or update on public.practice_plays
    for each row execute function public.stamp_practice_play_instructor();

-- ---------------------------------------------------------------------------
-- 2. creator_pools
-- ---------------------------------------------------------------------------
--
-- One row per month, written by the team in the SQL editor (runbook:
-- docs/CREATOR-PAYOUTS.md). No client reads it directly: a guide sees their
-- months through `guide_dashboard()`, which includes the pool.

create table if not exists public.creator_pools (
    -- The first day of the month, a UTC month.
    month         date        primary key check (extract(day from month) = 1),
    amount_cents  bigint      not null check (amount_cents >= 0),
    currency      text        not null default 'usd' check (currency ~ '^[a-z]{3}$'),
    -- When this month's shares were paid out. Null until they are.
    paid_at       timestamptz,
    -- For the team: where the figure came from ("Sept membership net of Apple").
    note          text,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

comment on table public.creator_pools is
    'The amount set aside for guides each month, split by minutes heard '
    '(creator_pool_shares). Written by the team; no client access (0026).';

drop trigger if exists creator_pools_updated_at on public.creator_pools;
create trigger creator_pools_updated_at
    before update on public.creator_pools
    for each row execute function public.handle_profile_updated_at();

-- RLS with no policies AND no grants, like `apple_credentials`: a client
-- request answers 42501, which proves the table exists.
alter table public.creator_pools enable row level security;
revoke all on public.creator_pools from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. creator_pool_shares
-- ---------------------------------------------------------------------------
--
-- Per guide, per month: seconds heard, everyone's seconds heard, and the
-- guide's cut of that month's pool when one is set. The payout run reads it
-- (`where month = …`), and so does `guide_dashboard()`.
--
-- ⚠️ Owner-rights (it adds up every member's plays), so its grants are its
-- only protection. Supabase grants ALL on a new view to `authenticated`, so
-- the revoke has to name it. Never grant this to a client role.

create or replace view public.creator_pool_shares as
with credited as (
    select p.instructor_id,
           (date_trunc('month', p.created_at at time zone 'UTC'))::date as month,
           p.seconds_played
      from public.practice_plays p
      left join public.instructors i on i.id = p.instructor_id
     where p.content_kind = 'session'
       and p.instructor_id is not null
       -- Not the guide's own listening. Null on either side (an anonymised
       -- play, a guide with no account linked) can't be the guide.
       and coalesce(p.user_id <> i.user_id, true)
),
by_guide as (
    select instructor_id, month, sum(seconds_played)::bigint as seconds_heard
      from credited
     group by instructor_id, month
),
by_month as (
    select month, sum(seconds_heard)::bigint as pool_seconds
      from by_guide
     group by month
)
select g.instructor_id,
       i.name,
       g.month,
       g.seconds_heard,
       m.pool_seconds,
       c.amount_cents as pool_cents,
       c.currency,
       c.paid_at,
       case when c.amount_cents is not null and m.pool_seconds > 0
            then floor(c.amount_cents::numeric * g.seconds_heard / m.pool_seconds)::bigint
       end as earned_cents
  from by_guide g
  join by_month m on m.month = g.month
  left join public.creator_pools c on c.month = g.month
  left join public.instructors i on i.id = g.instructor_id;

revoke all on public.creator_pool_shares from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. guide_dashboard()
-- ---------------------------------------------------------------------------
--
-- The caller's numbers if their account is linked to a guide, and no row
-- otherwise (a member, a guest, a guide with no account linked). A taken-down
-- guide still gets theirs: they can still be owed for months they were up.
--
-- Aggregates only. It never names, counts per person or identifies a member:
-- "people" is a distinct count, and nothing below it is broken down by member.
--
--   this_month   the running UTC month, which the app labels
--   totals       all time: people, plays, completions, seconds_heard (sessions)
--   months       every month from the guide's first credited play to now,
--                newest first, empty months included: people, plays,
--                completions, seconds_heard, pool_seconds, and the pool's
--                pool_cents / currency / paid_at / earned_cents (null while
--                no pool is set)
--   practices    per practice anyone opened: kind, id, title, people,
--                people_this_month, plays, completions, seconds_heard
--   programs     each digital retreat they lead: joined, finished

create or replace function public.guide_dashboard()
returns table (dashboard jsonb)
language sql
security definer
set search_path = public
stable
as $$
    with me as (
        select i.id, i.name, i.photo_url, i.user_id
          from public.instructors i
         where i.user_id = auth.uid()
           and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true
    ),
    clock as (
        select (date_trunc('month', now() at time zone 'UTC'))::date as this_month
    ),
    mine as (
        select p.content_kind, p.content_id, p.content_title, p.user_id,
               p.seconds_played, p.completed, p.created_at,
               (date_trunc('month', p.created_at at time zone 'UTC'))::date as month
          from public.practice_plays p
          join me on p.instructor_id = me.id
         where coalesce(p.user_id <> me.user_id, true)
    ),
    activity_by_month as (
        select month,
               count(distinct user_id)::integer           as people,
               count(*)::integer                          as plays,
               count(*) filter (where completed)::integer as completions
          from mine
         group by month
    ),
    calendar as (
        select gs::date as month
          from clock c,
               generate_series(coalesce((select min(month) from mine), c.this_month)::timestamp,
                               c.this_month::timestamp,
                               interval '1 month') gs
    ),
    month_rows as (
        select cal.month,
               coalesce(a.people, 0)        as people,
               coalesce(a.plays, 0)         as plays,
               coalesce(a.completions, 0)   as completions,
               coalesce(s.seconds_heard, 0) as seconds_heard,
               coalesce(s.pool_seconds, 0)  as pool_seconds,
               cp.amount_cents              as pool_cents,
               cp.currency,
               cp.paid_at,
               -- A pool with none of this guide's minutes in it is a zero, not
               -- an unknown.
               case when cp.amount_cents is not null then coalesce(s.earned_cents, 0) end as earned_cents
          from calendar cal
          left join activity_by_month a on a.month = cal.month
          left join public.creator_pool_shares s
                 on s.month = cal.month and s.instructor_id = (select id from me)
          left join public.creator_pools cp on cp.month = cal.month
    ),
    practice_rows as (
        select m.content_kind,
               m.content_id,
               (array_agg(m.content_title order by m.created_at desc))[1] as title,
               count(distinct m.user_id)::integer as people,
               (count(distinct m.user_id) filter (where m.month = (select this_month from clock)))::integer
                                                  as people_this_month,
               count(*)::integer                  as plays,
               (count(*) filter (where m.completed))::integer as completions,
               coalesce(sum(m.seconds_played) filter (where m.content_kind = 'session'), 0)::bigint
                                                  as seconds_heard
          from mine m
         group by m.content_kind, m.content_id
    ),
    program_rows as (
        select pr.id,
               pr.title,
               count(e.user_id)::integer      as joined,
               count(e.completed_at)::integer as finished
          from me
          join public.programs pr on pr.instructor_id = me.id
          left join public.program_enrollments e
                 on e.program_id = pr.id and e.user_id is distinct from me.user_id
         group by pr.id, pr.title
    )
    select jsonb_build_object(
        'instructor_id', me.id,
        'name',          me.name,
        'photo_url',     me.photo_url,
        'this_month',    (select this_month from clock),
        'totals',        (select jsonb_build_object(
                                     'people',        count(distinct user_id),
                                     'plays',         count(*),
                                     'completions',   count(*) filter (where completed),
                                     'seconds_heard', coalesce(sum(seconds_played)
                                                               filter (where content_kind = 'session'), 0))
                            from mine),
        'months',        coalesce((select jsonb_agg(to_jsonb(r) order by r.month desc)
                                     from month_rows r), '[]'::jsonb),
        'practices',     coalesce((select jsonb_agg(to_jsonb(x)
                                                    order by x.people desc, x.seconds_heard desc, x.title)
                                     from practice_rows x), '[]'::jsonb),
        'programs',      coalesce((select jsonb_agg(to_jsonb(y) order by y.joined desc, y.title)
                                     from program_rows y), '[]'::jsonb)
    )
    from me
$$;

revoke all on function public.guide_dashboard() from public, anon;
grant execute on function public.guide_dashboard() to authenticated;

-- ---------------------------------------------------------------------------
-- Verification (run each on its own; the Management API returns only the
-- last statement's rows)
-- ---------------------------------------------------------------------------
--
--   -- No client role can read the pools or the shares:
--   select table_name, grantee, privilege_type from information_schema.role_table_grants
--    where table_name in ('creator_pools', 'creator_pool_shares')
--      and grantee in ('anon', 'authenticated');                       -- 0 rows
--
--   -- The backfill left updated_at alone (compare with a count taken before):
--   select count(*) from public.practice_plays where updated_at > now() - interval '5 minutes';
--
--   -- Every session play with a guide now carries one, unless its creator
--   -- snapshot names someone else:
--   select p.creator, i.name, count(*) from public.practice_plays p
--     join public.practice_sessions s on s.id = p.content_id
--     join public.instructors i on i.id = s.instructor_id
--    where p.content_kind = 'session' and p.instructor_id is null
--    group by 1, 2;                                    -- only mismatched names
--
--   -- As a member linked to a guide (request.jwt.claims + role authenticated):
--   --   insert a session play sending instructor_id = 'someone-else' → stamped
--   --   with the session's own guide; PATCH instructor_id → unchanged;
--   --   select * from guide_dashboard() → one row; as an unlinked member and
--   --   as a guest → no rows; GET /rest/v1/creator_pools → 42501.
--
--   -- The payout run, for a closed month:
--   select name, seconds_heard, pool_seconds, earned_cents, currency
--     from public.creator_pool_shares
--    where month = date '2026-10-01'
--    order by earned_cents desc nulls last;
