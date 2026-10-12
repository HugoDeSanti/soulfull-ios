-- 0031_leave_program_atomically.sql
-- Leaving a digital retreat is one transaction.
--
-- The app left a program with two requests: delete the day completions, then
-- delete the enrolment. When the second failed (a dropped connection between
-- them), the server kept the enrolment with no completed days: the program
-- read as still joined, Day 1 open since the ORIGINAL join date, and any
-- practice finished since then completed it again on the next visit (latched,
-- with today's date). "Begin again" chains a leave into a join, so the member
-- silently restarted from a half-cleared slate.
--
-- `leave_program(p_program_id)` does both deletes in one statement batch, so
-- either both land or neither does. It is SECURITY INVOKER: the caller's own
-- RLS delete policies from 0013 still decide what goes ("Members leave
-- programs", "Members clear their own day completions"), so it can't touch
-- another member's rows, and a guest (who has none) deletes nothing. Like the
-- two deletes it replaces, it never touches `practice_plays`: the practices
-- were done and their guides earned from them.
--
-- The app calls it from `SupabaseService.leaveProgram`. Builds up to 1.0 (18)
-- still send the two deletes, which keep working.
--
-- How to apply: Management API (one transaction with its schema_migrations
-- row) or `supabase db push`. Safe to re-run.
--
-- APPLIED to the live project 2026-10-12 through the Management API, in one
-- transaction with its schema_migrations row (0031), after a dry run inside
-- an aborted transaction as the App Review member (enrolled in
-- finding-ground, given a finished day 1 for the test): enrolled 1 → 0 and
-- days 1 → 0 in one call; the owner's test account's enrolment untouched;
-- `anon` → 42501. After applying: authenticated may execute, anon may not,
-- SECURITY INVOKER, and PostgREST answers a guest's RPC with 42501 (not
-- PGRST202), so the schema cache has it. Build 1.0 (19), the first to call
-- it, was uploaded a few minutes earlier.
--
-- Verify after applying, as a member enrolled in a program with a completed
-- day, inside an aborted transaction:
--   select public.leave_program('<program id>');
--   select count(*) from public.program_enrollments    where user_id = auth.uid();  -- 0 for it
--   select count(*) from public.program_day_completions where user_id = auth.uid();  -- 0 for it
-- and as `anon`: `select public.leave_program('x')` → 42501 (no execute).

create or replace function public.leave_program(p_program_id text)
returns void
language sql
security invoker
set search_path = ''
as $$
    delete from public.program_day_completions
     where user_id = auth.uid()
       and program_id = p_program_id;

    delete from public.program_enrollments
     where user_id = auth.uid()
       and program_id = p_program_id;
$$;

revoke all on function public.leave_program(text) from public, anon;
grant execute on function public.leave_program(text) to authenticated;
