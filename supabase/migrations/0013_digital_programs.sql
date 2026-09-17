-- 0013_digital_programs.sql
-- The "Programs" tab: self-paced, multi-day guided journeys.
--
-- Spec: docs/PLAN-digital-programs.md
--
-- Three parts:
--   1. `programs` grows a curriculum (jsonb) + a published flag, and loses the
--      NOT NULL on `date_range` — a self-paced program has no calendar window.
--   2. `practice_sessions` grows `program_only`, so a program can carry media
--      that never appears on the Practice tab.
--   3. Two new per-member tables: enrolment, and day completion.
--
-- Nothing here touches `practice_plays`. A program day is membership state, not
-- a payable event; the activities *inside* a day record to the payout ledger
-- exactly as they do from the Practice tab, so creator earnings are unaffected.
--
-- APPLIED to the live project 2026-09-17 via the Management API, and recorded
-- in supabase_migrations.schema_migrations (0013) so the CLI stays in step.
--
-- Verified the same day, as a real member and as an anonymous guest:
--   • 7 policies, all `to authenticated`, none to `anon`.
--   • An ANONYMOUS GUEST (role=authenticated, is_anonymous=true — 0003's trap)
--     is refused with 42501 on insert. That is the server saying what
--     AccountGate says; a guest reaching this table means the gate failed open.
--   • A confirmed member enrols (201), completes a day, and CANNOT move the
--     completion date: re-inserting the way the app does (ignore-duplicates)
--     leaves `completed_at` untouched, and a PATCH matches zero rows because
--     no update policy exists. Both matter — that timestamp IS the next day's
--     unlock, so a writable one would let anyone hand themselves tomorrow.
--   • Another member's rows read back as [].
--   • Leaving deletes the enrolment and its day rows, and nothing else.
--
-- How to apply elsewhere: Supabase dashboard → SQL Editor, `supabase db push`,
-- or the Management API (`POST /v1/projects/<ref>/database/query`).

-- ---------------------------------------------------------------------------
-- 1. programs: the curriculum lives here
-- ---------------------------------------------------------------------------

alter table public.programs add column if not exists blurb       text;
alter table public.programs add column if not exists curriculum  jsonb;
alter table public.programs add column if not exists published   boolean not null default false;
alter table public.programs add column if not exists sort_order  integer;

-- 0006 declared this NOT NULL for a shelf that showed "Starts 12 Oct". These
-- programs are self-paced: the meta line is derived from `days` so it cannot
-- drift, and a row that sets `date_range` anyway is deliberately overriding it
-- (the same opt-out `retreats.experience.date_range` has).
alter table public.programs alter column date_range drop not null;

comment on column public.programs.curriculum is
    'The days and their activities. Hand-authored, snake_case keys, decoded by '
    'ProgramCurriculum in Models.swift. FAILS SOFT: a malformed document logs '
    'and yields a program with no days rather than breaking the catalog, so a '
    'program that shows no days is as likely to be broken as empty — check the '
    'log before assuming the column is null.';

comment on column public.programs.published is
    'Draft programs are invisible to the app. fetchPrograms() filters on this.';

-- ---------------------------------------------------------------------------
-- 2. practice_sessions: media that belongs to a program only
-- ---------------------------------------------------------------------------

alter table public.practice_sessions
    add column if not exists program_only boolean not null default false;

comment on column public.practice_sessions.program_only is
    'True = reachable only from inside a program curriculum; excluded from '
    'fetchPracticeSessions(category:) and from availablePracticeCategories(), '
    'so it never lights up or appears on the Practice tab.';

-- availablePracticeCategories() and the per-category list both filter on this,
-- so keep it in the category index.
drop index if exists practice_sessions_category_idx;
create index if not exists practice_sessions_category_idx
    on public.practice_sessions (category, program_only);

-- ---------------------------------------------------------------------------
-- 3. Per-member state
-- ---------------------------------------------------------------------------

create table if not exists public.program_enrollments (
    user_id      uuid        not null references auth.users (id) on delete cascade,
    program_id   text        not null references public.programs (id) on delete cascade,
    enrolled_at  timestamptz not null default now(),
    -- Set when the last day is completed. Null while the program is in flight.
    completed_at timestamptz,
    primary key (user_id, program_id)
);

create table if not exists public.program_day_completions (
    user_id      uuid        not null references auth.users (id) on delete cascade,
    program_id   text        not null references public.programs (id) on delete cascade,
    day_number   integer     not null check (day_number >= 1),
    completed_at timestamptz not null default now(),
    primary key (user_id, program_id, day_number)
);

-- The unlock rule reads "was the previous day completed, and on what date", so
-- every read is (user, program) ordered by day.
create index if not exists program_day_completions_member_idx
    on public.program_day_completions (user_id, program_id, day_number);

alter table public.program_enrollments     enable row level security;
alter table public.program_day_completions enable row level security;

-- Owner-only, and closed to anonymous guests.
--
-- Enrolling requires an account (AccountGate gates it client-side), and this is
-- the server saying the same thing. NOTE the shape of the anonymous check:
-- `is not true` rather than `= false`, so a JWT that simply omits the claim is
-- treated as a real account rather than locked out.
--
-- And note the role: `to authenticated` is correct here and `to anon` would be
-- wrong, but for the opposite reason to the catalog tables — anonymous guests
-- ARE the `authenticated` role (0003's trap), which is exactly why the
-- is_anonymous claim has to be checked explicitly.
drop policy if exists "Members read their own enrollments" on public.program_enrollments;
create policy "Members read their own enrollments"
    on public.program_enrollments
    for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Members enroll themselves" on public.program_enrollments;
create policy "Members enroll themselves"
    on public.program_enrollments
    for insert
    to authenticated
    with check (
        auth.uid() = user_id
        and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true
    );

drop policy if exists "Members update their own enrollments" on public.program_enrollments;
create policy "Members update their own enrollments"
    on public.program_enrollments
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Leaving a program is the member's right; unlike practice_plays there is
-- nothing here anyone else has a claim on.
drop policy if exists "Members leave programs" on public.program_enrollments;
create policy "Members leave programs"
    on public.program_enrollments
    for delete
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Members read their own day completions" on public.program_day_completions;
create policy "Members read their own day completions"
    on public.program_day_completions
    for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Members complete their own days" on public.program_day_completions;
create policy "Members complete their own days"
    on public.program_day_completions
    for insert
    to authenticated
    with check (
        auth.uid() = user_id
        and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true
    );

drop policy if exists "Members clear their own day completions" on public.program_day_completions;
create policy "Members clear their own day completions"
    on public.program_day_completions
    for delete
    to authenticated
    using (auth.uid() = user_id);

-- There is deliberately NO update policy on day completions: a completion date
-- is what the unlock rule reads, so moving it would move the gate. Days are
-- written once and cleared only by leaving the program.

-- Reuse the generic updated_at bumper from 0001_profiles.sql.
drop trigger if exists programs_set_updated_at on public.programs;
create trigger programs_set_updated_at
    before update on public.programs
    for each row execute function public.handle_profile_updated_at();

-- ---------------------------------------------------------------------------
-- Verification (run after applying)
--
--   -- new columns present
--   select column_name, is_nullable from information_schema.columns
--    where table_name = 'programs' order by ordinal_position;
--
--   -- both tables locked down: 4 policies each, none granted to anon
--   select tablename, policyname, cmd, roles from pg_policies
--    where tablename in ('program_enrollments', 'program_day_completions');
--
--   -- an anon-key insert must fail (42501), NOT succeed
-- ---------------------------------------------------------------------------
