-- 0022_written_practice_guides.sql
-- A written practice names its guide on its own row, the way a session and a
-- digital retreat do (0019) — and `practice_credits` (0020) goes.
--
-- 0020 existed because journal prompts, movement sequences and recipes were
-- Swift arrays with no row to carry an `instructor_id`, so a credit had to be
-- a row of its own, keyed by (content_kind, content_id) with no foreign key to
-- the practice. Since 0021 they are tables, and the side table is all cost:
-- a credit could name a practice that didn't exist, crediting a new practice
-- was two inserts in two tables, and "who made this" was answered differently
-- for written practices than for everything else.
--
--   1. `instructor_id` on `journal_prompts`, `exercises` and `recipes`, a real
--      foreign key, `on delete set null` exactly like 0019's: taking a guide
--      down leaves their practices up, with no guide on the page.
--   2. The 13 existing credits copied across.
--   3. `practice_credits` dropped.
--
-- Still DISPLAY ONLY. The written libraries record no creator in the practice
-- ledger (`creditsCreator` in Swift) and naming a guide on the row doesn't
-- change that. Unlike a session's, a written practice has no `lead` for a
-- trigger to keep in step with the guide's name.
--
-- Safe to drop: no function or view reads `practice_credits`, and no build
-- outside development ever did — the instructor code first ships in 1.0 (11),
-- which reads the column instead.
--
-- APPLIED 2026-09-29 through the Management API and recorded in
-- supabase_migrations.schema_migrations (0022), after a dry run inside a
-- rolled-back transaction. Verified live: all 13 credits landed on the row
-- they named and no other row gained a guide; an unknown guide is refused
-- (23503); the client roles still hold SELECT only — a guest reads
-- `instructor_id` (200) and can't PATCH it (401); `practice_credits` answers
-- 404. In the app, a live digital retreat's guide opened a profile listing
-- that guide's written practices from their rows.

-- ---------------------------------------------------------------------------
-- 1. The column
-- ---------------------------------------------------------------------------

alter table public.journal_prompts
    add column if not exists instructor_id text references public.instructors (id) on delete set null;
alter table public.exercises
    add column if not exists instructor_id text references public.instructors (id) on delete set null;
alter table public.recipes
    add column if not exists instructor_id text references public.instructors (id) on delete set null;

-- A guide's page lists what they made.
create index if not exists journal_prompts_instructor_idx
    on public.journal_prompts (instructor_id) where instructor_id is not null;
create index if not exists exercises_instructor_idx
    on public.exercises (instructor_id) where instructor_id is not null;
create index if not exists recipes_instructor_idx
    on public.recipes (instructor_id) where instructor_id is not null;

comment on column public.journal_prompts.instructor_id is
    'The guide shown on this prompt''s page and in their library. Display only — no payout.';
comment on column public.exercises.instructor_id is
    'The guide shown on this sequence''s page and in their library. Display only — no payout.';
comment on column public.recipes.instructor_id is
    'The guide shown on this recipe''s page and in their library. Display only — no payout.';

-- No grant needed: 0021 granted SELECT on each whole table to both client
-- roles, which covers a new column, and still nothing else.

-- ---------------------------------------------------------------------------
-- 2. The credits, copied across
-- ---------------------------------------------------------------------------
--
-- Guarded on the table still existing, so a re-run after step 3 is a no-op
-- rather than an error.

do $$
begin
    if to_regclass('public.practice_credits') is not null then
        update public.journal_prompts t set instructor_id = c.instructor_id
          from public.practice_credits c
         where c.content_kind = 'journal' and c.content_id = t.id and t.instructor_id is null;
        update public.exercises t set instructor_id = c.instructor_id
          from public.practice_credits c
         where c.content_kind = 'exercise' and c.content_id = t.id and t.instructor_id is null;
        update public.recipes t set instructor_id = c.instructor_id
          from public.practice_credits c
         where c.content_kind = 'recipe' and c.content_id = t.id and t.instructor_id is null;
    end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. The side table, gone
-- ---------------------------------------------------------------------------

drop table if exists public.practice_credits;

-- ---------------------------------------------------------------------------
-- Verification (each on its own)
-- ---------------------------------------------------------------------------
--
--   -- The 13 credits, now on their rows:
--   select 'journal' kind, id, instructor_id from journal_prompts union all
--   select 'exercise', id, instructor_id from exercises union all
--   select 'recipe', id, instructor_id from recipes order by 1, 2;
--   -- A guide who doesn't exist is refused (23503):
--   update recipes set instructor_id = 'nobody' where id = 1;
--   -- As a guest: GET /rest/v1/exercises?select=id,instructor_id → 200; PATCH → 42501.
--   -- GET /rest/v1/practice_credits → 404 (PGRST205), the table is gone.
