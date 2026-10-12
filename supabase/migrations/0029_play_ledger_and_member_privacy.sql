-- 0029_play_ledger_and_member_privacy.sql
-- Closes the holes the 2026-10-11 app review found in what a client can write
-- to the payout ledger and read about other members. Five parts:
--
--   1. `practice_plays` — the server says what was played. An insert used to
--      take its length, title, creator, category and dates from the client,
--      and the length was the only bound on `seconds_played`: one REST call
--      with `duration_seconds: 2000000000` handed a guide the whole month's
--      pool, a backdated `created_at` rewrote a month already paid, and a
--      free-text `content_title` went in front of every member through the
--      feed. Now:
--        • only a permanent account may write a play (a guest can't open a
--          practice in the app, so a guest's play is never real);
--        • the title, creator, category and length come from the catalog row,
--          and a play of something that doesn't exist is refused (23503);
--        • `created_at` / `started_at` are the server's clock;
--        • `seconds_played` can't run ahead of the time since the play began
--          (plus two minutes for heartbeats that failed and were retried);
--        • a play more than a day old is closed: its seconds and completion
--          no longer move, so a past month's shares can't be topped up later;
--        • `completed_at` is new, stamped once when `completed` latches.
--   2. `practice_progress` gains `last_completed_at` = max(completed_at). A
--      digital-retreat day counts an activity only if it was FINISHED after
--      the day unlocked. It used to read `completed and last_played_at >=
--      unlocked`, and `completed` is latched for all time while
--      `last_played_at` moves on any open — so opening last month's session
--      for two seconds finished today's day (and the day's completion is
--      latched too).
--   3. `community_activity` orders by `completed_at` (it used `updated_at`,
--      which any no-op PATCH moved, re-floating old lines to the top of
--      everyone's feed) and shows the last 30 days only. It used to serve a
--      member's whole history to anyone with a session, guests included.
--   4. `community_members`: a guest sees only the members the feed already
--      shows them (shared, finished, non-journal practice in the last 30
--      days). Before, any guest could page through every member's id, name
--      and photo. Members are unchanged.
--   5. The `practice-media` bucket is readable by members only. Its policy
--      was `to anon, authenticated`, so the anon key in the IPA, with no
--      session at all, downloaded the library the app gates behind an account.
--
-- Plus `member_reports.reporter_is_guest`, which `report-member` uses to give
-- guests one shared hourly allowance: a guest id is free, so a per-reporter
-- limit alone let a loop of anonymous sign-ins email the team without end.
--
-- Not changed, on purpose: a member can still run several plays at once, each
-- bounded as above. Defending payouts against a determined member needs the
-- Storage access-log check in supabase/functions/README.md.
--
-- How to apply: Management API (one transaction with its schema_migrations
-- row) or `supabase db push`. Safe to re-run. Apply BEFORE deploying the
-- `report-member` version that writes `reporter_is_guest`.
--
-- APPLIED to the live project 2026-10-11 through the Management API, in one
-- transaction with its schema_migrations row (0029), after a dry run inside an
-- aborted transaction that ran the checks at the bottom as the App Review
-- member and a guest. All held: a guest's insert → 42501; a member's insert
-- claiming 2,000,000,000 seconds, a forged title and creator and a January
-- date → the catalog's title, creator and 128 s length, today's dates, 120 s;
-- unknown content → 23503; an upsert ten minutes in → past the insert's
-- 120 s to the full 128 (so the EXCLUDED path isn't capped); a two-day-old
-- play → seconds and completion unchanged; completed_at and last_completed_at
-- set; community_members 1 row for a guest, 5 for a member; practice-media
-- objects visible to anon 0, guest 0, member 3; no finished play left without
-- completed_at after the backfill. After applying: the columns, policies,
-- indexes and SECURITY DEFINER trigger are in place; with the anon key a
-- practice-media sign and a direct GET answer 400 (they answered 206 before);
-- `report-member` v2 deployed after it, JWT verification on (401 without one).


-- ===========================================================================
-- 1. practice_plays
-- ===========================================================================

alter table public.practice_plays
    add column if not exists completed_at timestamptz;

comment on column public.practice_plays.completed_at is
    'When this play was first recorded as finished. Stamped by the integrity trigger, never by a client.';

-- Backfill with the integrity trigger OFF: it sets `updated_at = now()`, and
-- `practice_progress.last_played_at` (max updated_at) is what every member's
-- Continue card and resume point read. `updated_at` is the closest record of
-- when an old play finished.
alter table public.practice_plays disable trigger practice_plays_integrity;
update public.practice_plays
   set completed_at = updated_at
 where completed and completed_at is null;
alter table public.practice_plays enable trigger practice_plays_integrity;

-- SECURITY DEFINER so the catalog lookup sees the row whatever the caller may
-- read: a program-only session, or a practice unpublished while someone was
-- in the middle of it. It reads four columns and returns nothing.
create or replace function public.enforce_practice_play_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_title    text;
    v_creator  text;
    v_category text;
    v_duration integer;
    -- What `seconds_played` may run ahead of the time since the play began:
    -- room for a few failed heartbeats whose total lands with a later one.
    slack constant integer := 120;
    earlier integer := 0;
begin
    if tg_op = 'INSERT' then
        -- What was played comes from the catalog, never the client. These
        -- mirror `PracticePlay`'s factories in Models.swift: a journal prompt's
        -- nominal 900 seconds, a recipe's cooking time.
        case new.content_kind
            when 'session' then
                select s.title, s.lead, s.category, s.duration_seconds
                  into v_title, v_creator, v_category, v_duration
                  from public.practice_sessions s
                 where s.id = new.content_id;
            when 'journal' then
                select t.title, 900
                  into v_title, v_duration
                  from public.journal_prompts t
                 where t.id = new.content_id;
            when 'exercise' then
                select t.title, t.duration_seconds
                  into v_title, v_duration
                  from public.exercises t
                 where t.id = new.content_id;
            when 'recipe' then
                select t.title, t.minutes * 60
                  into v_title, v_duration
                  from public.recipes t
                 where t.id = new.content_id;
            else
                -- 'massage': retired (0012), kept in the check only so old
                -- rows stay valid. Nothing new is recorded against it.
                null;
        end case;

        if v_title is null then
            raise exception 'practice_plays: % % is not a practice', new.content_kind, new.content_id
                using errcode = '23503';
        end if;

        new.content_title    := v_title;
        new.creator          := v_creator;
        new.category         := v_category;
        new.duration_seconds := v_duration;
        new.started_at       := now();
        new.created_at       := now();
        new.completed_at     := case when new.completed then now() end;

        -- ⚠️ Every heartbeat is an upsert, and an upsert runs this branch on
        -- the row it proposes BEFORE finding the row it will update — what this
        -- branch leaves is what EXCLUDED hands the update. Bounding seconds
        -- here would cap every play at its first two minutes, so a play that
        -- already exists goes to the update branch as the client sent it,
        -- and that branch bounds it against its own start.
        if exists (select 1 from public.practice_plays p
                    where p.user_id = new.user_id
                      and p.client_event_id = new.client_event_id) then
            return new;
        end if;
    else
        -- Frozen identity.
        new.id              := old.id;
        -- `user_id` is frozen ONLY against being re-pointed at another member.
        -- A NULL must be allowed through: it is how ON DELETE SET NULL
        -- anonymises this row when the member deletes their account. RLS's
        -- `with check (auth.uid() = user_id)` refuses a client nulling its own.
        if new.user_id is not null then
            new.user_id     := old.user_id;
        end if;
        new.content_kind     := old.content_kind;
        new.content_id       := old.content_id;
        new.creator          := old.creator;
        new.client_event_id  := old.client_event_id;
        new.started_at       := old.started_at;
        new.created_at       := old.created_at;
        new.content_title    := old.content_title;
        new.category         := old.category;
        new.duration_seconds := coalesce(old.duration_seconds, new.duration_seconds);
        new.completed_at     := old.completed_at;
        earlier              := old.seconds_played;

        if old.started_at < now() - interval '1 day' then
            -- Closed. A play's seconds land in the month it was created in, so
            -- topping up an old row would move a month that may be paid.
            new.seconds_played := old.seconds_played;
            new.completed      := old.completed;
        else
            -- Monotonic consumption, latching completion.
            new.seconds_played := greatest(new.seconds_played, old.seconds_played);
            new.completed      := new.completed or old.completed;
            if new.completed and not old.completed then
                new.completed_at := now();
            end if;
        end if;
    end if;

    -- No faster than real time: nobody hears more of a practice than the time
    -- since they started it.
    new.seconds_played := least(
        new.seconds_played,
        greatest(earlier, ceil(extract(epoch from (now() - new.started_at)))::integer + slack)
    );

    -- Never more than the practice is long.
    if new.duration_seconds is not null then
        new.seconds_played   := least(new.seconds_played,   new.duration_seconds);
        new.position_seconds := least(new.position_seconds, new.duration_seconds);
    end if;

    new.updated_at := now();
    return new;
end;
$$;

revoke all on function public.enforce_practice_play_integrity() from public, anon, authenticated;

-- (The trigger itself is unchanged since 0008; only the function body moved.)

-- A guest can't open a practice in the app, so a guest's play is never a real
-- one. `caller_has_account()` reads auth.users rather than the JWT claim
-- (0023), and the subselect evaluates it once per statement.
drop policy if exists "Members record their own plays" on public.practice_plays;
create policy "Members record their own plays"
    on public.practice_plays
    for insert
    to authenticated
    with check (auth.uid() = user_id and (select public.caller_has_account()));

drop policy if exists "Members update their own in-flight plays" on public.practice_plays;
create policy "Members update their own in-flight plays"
    on public.practice_plays
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id and (select public.caller_has_account()));

-- The feed reads "finished, newest first" and "finished by these people", now
-- by when they finished. These replace 0015's `updated_at` pair, which every
-- heartbeat had to maintain for nothing.
create index if not exists practice_plays_finished_recent_idx
    on public.practice_plays (completed_at desc)
    where completed;
create index if not exists practice_plays_finished_by_member_idx
    on public.practice_plays (user_id, completed_at desc)
    where completed;
drop index if exists public.practice_plays_completed_recent_idx;
drop index if exists public.practice_plays_completed_by_member_idx;


-- ===========================================================================
-- 2. practice_progress
-- ===========================================================================
--
-- 0008's view, unchanged, plus `last_completed_at` at the end (a replaced view
-- may only add columns after the existing ones).
--
-- ⚠️ `security_invoker = on` is load-bearing — see 0008.

create or replace view public.practice_progress
with (security_invoker = on) as
select
    p.user_id,
    p.content_kind,
    p.content_id,
    (array_agg(p.content_title    order by p.updated_at desc))[1] as content_title,
    (array_agg(p.creator          order by p.updated_at desc))[1] as creator,
    (array_agg(p.category         order by p.updated_at desc))[1] as category,
    (array_agg(p.position_seconds order by p.updated_at desc))[1] as position_seconds,
    max(p.duration_seconds)                                       as duration_seconds,
    sum(p.seconds_played)::bigint                                 as total_seconds_played,
    bool_or(p.completed)                                          as completed,
    count(*)::integer                                             as play_count,
    max(p.updated_at)                                             as last_played_at,
    -- When it was last FINISHED, which is not when it was last opened.
    max(p.completed_at)                                           as last_completed_at
from public.practice_plays p
where p.user_id is not null
group by p.user_id, p.content_kind, p.content_id;

grant select on public.practice_progress to authenticated;


-- ===========================================================================
-- 3. community_activity
-- ===========================================================================
--
-- Same columns as 0016. `completed_at` is now the real moment, and the feed is
-- the last 30 days: "what the circle is practicing", not an archive of each
-- member's routine. A friend quiet for longer than that drops out of the
-- Friends feed until they practice again.

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
    pl.completed_at,
    (select count(*) from public.practice_play_likes l where l.play_id = pl.id)::integer as like_count,
    exists (select 1 from public.practice_play_likes l
            where l.play_id = pl.id and l.user_id = auth.uid())               as liked_by_me
from public.practice_plays pl
join public.community_members m on m.id = pl.user_id
join public.profiles p on p.id = pl.user_id
where pl.completed
  and pl.completed_at > now() - interval '30 days'
  and pl.content_kind <> 'journal'
  and p.share_activity;

revoke all on public.community_activity from anon, authenticated, public;
grant select on public.community_activity to authenticated;


-- ===========================================================================
-- 4. community_members
-- ===========================================================================
--
-- 0028's view (blocks filtered both ways), plus: a guest sees only the
-- members the feed already shows them. Everything that joins this view keeps
-- working for a guest — the feed's own authors pass the same test — and a
-- guest's presence and follower faces narrow to members who have shared a
-- finished practice this month. Members see what they saw before.

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
  )
  and (
      (select public.caller_has_account())
      or (p.share_activity and exists (
          select 1 from public.practice_plays pl
          where pl.user_id = p.id
            and pl.completed
            and pl.completed_at > now() - interval '30 days'
            and pl.content_kind <> 'journal'
      ))
  );

revoke all on public.community_members from anon, authenticated, public;
grant select on public.community_members to authenticated;


-- ===========================================================================
-- 5. practice-media
-- ===========================================================================
--
-- Signing a URL needs SELECT on the object, so this is also who can play.
-- The app opens a session only for an account (`AccountGate`).

drop policy if exists "Practice media is readable by app users" on storage.objects;
drop policy if exists "Practice media is readable by members" on storage.objects;
create policy "Practice media is readable by members"
    on storage.objects
    for select
    to authenticated
    using (bucket_id = 'practice-media' and (select public.caller_has_account()));


-- ===========================================================================
-- Plus: member_reports.reporter_is_guest
-- ===========================================================================

alter table public.member_reports
    add column if not exists reporter_is_guest boolean not null default false;

comment on column public.member_reports.reporter_is_guest is
    'Filed from an anonymous guest session. report-member gives guests one shared hourly allowance.';

create index if not exists member_reports_guest_recent_idx
    on public.member_reports (created_at desc)
    where reporter_is_guest;


-- ---------------------------------------------------------------------------
-- Checks (run as a member M with a session S, a guest G, and anon)
-- ---------------------------------------------------------------------------
--
-- Plays:
--   G inserts a play                                  → 42501 (RLS)
--   M inserts { content_id: S, duration_seconds: 2000000000, seconds_played:
--     2000000000, content_title: 'x', created_at: '2026-01-01' }
--                                                     → title/duration from S,
--     created_at/started_at = now(), seconds_played = 120
--   M inserts content_id 9999999                      → 23503
--   M updates the same row 10 s later to 2000000000   → seconds = 130 (+120)
--   M updates a row whose started_at is 2 days ago    → seconds/completed unchanged
--   completed false → true                            → completed_at stamped once
-- Progress: last_completed_at = max(completed_at); an open after it leaves it.
-- Feed: a completion 31 days old is absent; completed_at orders it.
-- Members: G reads community_members → only members in G's feed; M → as before.
-- Storage: anon / G sign or GET a practice-media object → refused; M → 200.
