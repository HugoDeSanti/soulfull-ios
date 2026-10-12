-- 0030_name_limit_and_self_play.sql
-- The two things the 2026-10-11 review left open on the server:
--
--   1. Names have a ceiling: 64 characters, for a member (`profiles.full_name`)
--      and a guide (`instructors.name`). A member's name reaches everyone
--      through the feed, and a linked guide's is copied onto every page they
--      made (0027), and nothing bounded either. A member's name is trimmed and
--      cut to 64 by a trigger rather than refused, so no sign-up, Apple name
--      or older app's profile write can fail on it; the check constraint is
--      the guarantee underneath. A guide the team names is refused past 64
--      instead: that is someone at the SQL editor, who should see why. The app
--      caps its name fields at the same 64 (`MemberName`, counted in code
--      points like `char_length`).
--   2. A guide's own listening is judged when it happens. `creator_pool_shares`
--      and `guide_dashboard()` compared each play's member with the guide's
--      account as it is TODAY, so unlinking a guide, or the guide deleting
--      their account (their plays' user_id goes null), turned every second
--      they ever played of their own sessions into payable time, back through
--      months already paid. `practice_plays.self_play` is now stamped at
--      insert, by the trigger that stamps `instructor_id`, and frozen with it.
--
-- How to apply: Management API (one transaction with its schema_migrations
-- row) or `supabase db push`. Safe to re-run.
--
-- NOT YET APPLIED (written 2026-10-11).


-- ===========================================================================
-- 1. Names
-- ===========================================================================

create or replace function public.bound_profile_name()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.full_name is not null then
        new.full_name := btrim(left(btrim(new.full_name, E' \t\r\n'), 64), E' \t\r\n');
    end if;
    return new;
end;
$$;

revoke all on function public.bound_profile_name() from public, anon, authenticated;

drop trigger if exists profiles_bound_name on public.profiles;
create trigger profiles_bound_name
    before insert or update of full_name on public.profiles
    for each row execute function public.bound_profile_name();

-- Any name already longer goes through the trigger above. A linked guide's
-- name follows (0027's `profiles_guide_name`).
update public.profiles
   set full_name = full_name
 where char_length(full_name) > 64;

alter table public.profiles drop constraint if exists profiles_full_name_length;
alter table public.profiles
    add constraint profiles_full_name_length
    check (full_name is null or char_length(full_name) <= 64);

-- A guide the team names. A linked guide's name is the account's (0027), now
-- within 64 already.
update public.instructors
   set name = btrim(left(btrim(name), 64))
 where char_length(name) > 64;

alter table public.instructors drop constraint if exists instructors_name_length;
alter table public.instructors
    add constraint instructors_name_length
    check (char_length(name) <= 64);


-- ===========================================================================
-- 2. self_play
-- ===========================================================================

alter table public.practice_plays
    add column if not exists self_play boolean not null default false;

comment on column public.practice_plays.self_play is
    'The guide this play credits (instructor_id) was the one playing it, as linked when it happened. '
    'Stamped at insert with instructor_id and frozen; such plays earn nothing (creator_pool_shares).';

-- Plays before today, from today's links: the best record there is of which
-- account was the guide's. With the integrity trigger OFF, because it moves
-- `updated_at`, which every resume point and program day reads (0026 did the
-- same). The stamp trigger still runs, as 0026 left it, and doesn't touch
-- this column — which is why this comes before it is replaced below.
alter table public.practice_plays disable trigger practice_plays_integrity;
update public.practice_plays p
   set self_play = true
  from public.instructors i
 where i.id = p.instructor_id
   and i.user_id is not null
   and p.user_id = i.user_id
   and not p.self_play;
alter table public.practice_plays enable trigger practice_plays_integrity;

-- 0026's stamp, plus `self_play` beside `instructor_id`. An upsert runs the
-- INSERT branch on the row it proposes and the UPDATE branch on the row it
-- finds, which freezes both from OLD — so a heartbeat can't restamp either.
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
        -- The guide hearing their own work, judged now and kept: whether it
        -- earns can't change when the guide's account is later unlinked or
        -- deleted.
        new.self_play := coalesce(
            new.user_id = (select i.user_id from public.instructors i where i.id = new.instructor_id),
            false);
    else
        -- Frozen, unconditionally (see 0026).
        new.instructor_id := old.instructor_id;
        new.self_play     := old.self_play;
    end if;
    return new;
end;
$$;

revoke all on function public.stamp_practice_play_instructor() from public, anon, authenticated;

-- 0026's view; only the self-play test changed.
create or replace view public.creator_pool_shares as
with credited as (
    select p.instructor_id,
           (date_trunc('month', p.created_at at time zone 'UTC'))::date as month,
           p.seconds_played
      from public.practice_plays p
     where p.content_kind = 'session'
       and p.instructor_id is not null
       -- Not the guide's own listening, as judged when the play happened.
       and not p.self_play
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

-- 0026's function; only the self-play test changed.
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
         where not p.self_play
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
-- Checks
-- ---------------------------------------------------------------------------
--
-- Names: a member's upsert of 70 characters → stored as 64; a sign-up whose
-- metadata name is 70 → profile created with 64; `update instructors set name
-- = <70 chars>` on an unlinked guide → 23514. No name longer than 64 remains.
-- self_play: a linked guide playing their own session → self_play true; a
-- member playing it → false; a PATCH of self_play → unchanged. Unlinking the
-- guide (user_id = null) leaves creator_pool_shares and guide_dashboard()'s
-- figures for past months as they were.
