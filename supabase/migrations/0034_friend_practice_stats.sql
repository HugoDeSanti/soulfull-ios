-- 0034_friend_practice_stats.sql
-- A friend's practice in numbers: their streak, their best streak, the
-- classes they've taken and their minutes in class, the same four figures
-- they see on their own You tab. Read through one function,
-- `friend_practice_stats(tz)`, which answers one row per friend.
--
--   1. Friends only: an ACCEPTED friendship with the caller, either way round,
--      and the caller a member (`caller_has_account()`; a guest has no
--      friends anyway). A pending request sees nothing, and neither does
--      anyone else. Through `community_members`, so a block either way ends
--      it at once, as it ends the friendship.
--   2. Only from a friend who shares their practice (`profiles.share_activity`,
--      the "Share my practice" switch). Turning it off takes them out of the
--      feed and out of this. A friend who doesn't share has no row at all,
--      so the app says they keep their practice to themselves.
--   3. Numbers, never a calendar or a title. What leaves the database is the
--      latest run of practice days (its first and last day), the longest run
--      ever, the classes and the minutes. Not which practices, not when in the
--      day, not one row per day: 0029 made the feed "what the circle is
--      practicing", not an archive of each member's routine, and a list of
--      every day someone practiced would be that archive. The app works the
--      current streak out of the latest run against its own today, so it moves
--      at midnight with the You tab's, without a second read.
--   4. The same rules as `PracticeStats` (PracticeProgressStore.swift), which
--      counts a member's own: a practice day is a day on which ANY practice was
--      finished, journal prompts and recipes included (a prompt's title never
--      leaves the database, and a friend's streak has to be the number they
--      see themselves), dated by when it was finished, or begun for a row from
--      before 0029; a class is a finished session or movement sitting
--      (`countsAsClass`); minutes are seconds spent in those classes, finished
--      or not, rounded down. Change one, change both.
--   5. The days are counted in the CALLER's time zone (`tz`, an IANA name the
--      app sends; anything Postgres doesn't know counts in UTC). A member's own
--      streak is counted in their own phone's zone, so for a friend in another
--      zone the two can differ by a day at the edges. Storing each member's
--      zone would fix that and tell their friends where they are; it isn't
--      worth it.
--
-- How to apply: Management API (one transaction with its schema_migrations
-- row) or `supabase db push`. Safe to re-run.
--
-- NOT APPLIED YET.


-- ===========================================================================
-- friend_practice_stats(tz)
-- ===========================================================================

create or replace function public.friend_practice_stats(tz text default 'UTC')
returns table (
    friend_id         uuid,
    run_first_day     date,
    run_last_day      date,
    best_streak       integer,
    classes_taken     integer,
    minutes_practiced integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    zone text := 'UTC';
begin
    if auth.uid() is null or not public.caller_has_account() then
        return;
    end if;

    -- An unknown zone name would fail the whole read; it counts in UTC instead.
    if tz is not null then
        begin
            perform now() at time zone tz;
            zone := tz;
        exception when others then
            zone := 'UTC';
        end;
    end if;

    return query
    with friends as (
        select case when f.requester_id = auth.uid() then f.addressee_id
                    else f.requester_id end as id
        from public.friendships f
        where f.status = 'accepted'
          and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
    ),
    sharing as (
        select fr.id
        from friends fr
        join public.profiles p on p.id = fr.id
        -- Blocks, either way (0028).
        join public.community_members m on m.id = fr.id
        where p.share_activity
    ),
    days as (
        select distinct pl.user_id,
               (coalesce(pl.completed_at, pl.started_at) at time zone zone)::date as day
        from public.practice_plays pl
        join sharing s on s.id = pl.user_id
        where pl.completed
    ),
    -- Gaps and islands: consecutive days share `day - row number`.
    runs as (
        select d.user_id, min(d.day) as first_day, max(d.day) as last_day,
               count(*)::integer as length
        from (select user_id, day,
                     day - (row_number() over (partition by user_id order by day))::integer as island
              from days) d
        group by d.user_id, d.island
    ),
    latest as (
        select distinct on (r.user_id) r.user_id, r.first_day, r.last_day
        from runs r
        order by r.user_id, r.last_day desc
    ),
    longest as (
        select r.user_id, max(r.length) as length
        from runs r
        group by r.user_id
    ),
    classes as (
        select pl.user_id,
               (count(*) filter (where pl.completed))::integer as finished,
               (coalesce(sum(greatest(pl.seconds_played, 0)), 0) / 60)::integer as minutes
        from public.practice_plays pl
        join sharing s on s.id = pl.user_id
        where pl.content_kind in ('session', 'exercise')
        group by pl.user_id
    )
    select s.id,
           l.first_day,
           l.last_day,
           coalesce(g.length, 0),
           coalesce(c.finished, 0),
           coalesce(c.minutes, 0)
    from sharing s
    left join latest l on l.user_id = s.id
    left join longest g on g.user_id = s.id
    left join classes c on c.user_id = s.id;
end;
$$;

revoke all on function public.friend_practice_stats(text) from public, anon;
grant execute on function public.friend_practice_stats(text) to authenticated;


-- ===========================================================================
-- Verification (run after applying)
-- ===========================================================================
--
--   -- grants: authenticated only
--   select grantee, privilege_type from information_schema.routine_privileges
--    where routine_name = 'friend_practice_stats';
--
--   -- as a member with friends (set request.jwt.claims + role authenticated):
--   select * from public.friend_practice_stats('Europe/Madrid');
--   -- one row per accepted friend who shares; none for a pending request, a
--   -- non-friend, a friend with share_activity off, or after a block; nothing
--   -- for a guest or anon. A bad zone ('Mars/Olympus') answers as UTC.
