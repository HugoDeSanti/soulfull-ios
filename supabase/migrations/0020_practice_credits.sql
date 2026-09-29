-- 0020_practice_credits.sql
-- Which guide a written practice — a journal prompt, a movement sequence, a
-- recipe — is credited to, so its page can show "Your guide".
--
-- Those three libraries live in Swift, not in tables (`JournalPrompt.all`,
-- `Exercise.all`, `Recipe.all`), so there is no row to hang an
-- `instructor_id` on the way 0019 does for sessions and programs. This table
-- is that row: one credit per practice, keyed by the same
-- (content_kind, content_id) pair the ledger and presence use. Crediting or
-- re-crediting a practice is a data change, never a release.
--
-- DISPLAY ONLY. It does not touch `practice_plays.creator` or any payout:
-- the written libraries record a null creator (`creditsCreator` in Swift),
-- and naming a guide on a page does not change that. If written content is
-- ever paid for, that is a decision about the ledger, not about this table.
--
-- Sessions are deliberately not credited here — a session row carries its own
-- `instructor_id` (0019), which also keeps its `lead`, the payout snapshot,
-- in step. The check constraint keeps the two mechanisms from overlapping.
--
-- `on delete cascade`: taking a guide down takes their credits with them, and
-- those pages simply show no guide.

create table if not exists public.practice_credits (
    content_kind  text    not null check (content_kind in ('journal', 'exercise', 'recipe')),
    content_id    integer not null,
    instructor_id text    not null references public.instructors (id) on delete cascade,
    created_at    timestamptz not null default now(),
    primary key (content_kind, content_id)
);

create index if not exists practice_credits_instructor_idx
    on public.practice_credits (instructor_id);

alter table public.practice_credits enable row level security;

-- Catalog: both client roles read it (an anonymous guest is `authenticated`,
-- 0003's trap). No write policy — the team writes it in the dashboard.
drop policy if exists "Practice credits are public" on public.practice_credits;
create policy "Practice credits are public"
    on public.practice_credits
    for select
    to anon, authenticated
    using (true);

revoke all on public.practice_credits from anon, authenticated, public;
grant select on public.practice_credits to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Verification (each on its own)
-- ---------------------------------------------------------------------------
--
--   -- Read-only to clients:
--   select grantee, privilege_type from information_schema.role_table_grants
--    where table_name = 'practice_credits' and grantee in ('anon', 'authenticated');
--                                              -- SELECT for each, nothing else
--   -- As a guest: GET /rest/v1/practice_credits → 200; POST → 42501.
--   -- A session credit is refused:
--   insert into public.practice_credits values ('session', 1, '<id>');  -- 23514
