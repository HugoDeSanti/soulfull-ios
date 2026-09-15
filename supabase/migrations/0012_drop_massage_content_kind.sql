-- ---------------------------------------------------------------------------
-- 0012 — narrow practice_plays.content_kind to the libraries that still ship
-- ---------------------------------------------------------------------------
--
-- APPLIED to the live project 2026-09-15 and verified: the constraint rejects
-- 'massage' (23514) and accepts 'exercise'; both existing plays (one journal,
-- one recipe) were untouched. Recorded in `supabase_migrations.schema_migrations`
-- by hand, because `supabase db push` refuses to run against this project —
-- 0001–0009 are recorded remotely but their files were deleted from the repo on
-- 2026-09-07, and the CLI's suggested `migration repair --status reverted` would
-- falsify the record by claiming applied migrations were rolled back. Don't run
-- that. Apply a new migration the same way this one was, or temporarily restore
-- 0001–0009 (`git show d20e3f6:supabase/migrations/`) so the CLI is satisfied.
--
-- The Personal Massages section was removed from the app on 2026-09-15. Its
-- Swift case (`PracticeContentKind.massage`) went with it, so no client can
-- produce a 'massage' row any more — but 0008's check constraint still accepts
-- one. This narrows the constraint so the schema says the same thing the app
-- does.
--
-- WHY THIS IS SAFE TO DO AT ALL: the app has no users yet, so there is no
-- massage history to preserve. Had there been any, the case would have had to
-- stay — `practice_plays` rows are the record creator payouts are drawn from,
-- they are deliberately never deleted, and a kind the client can't decode falls
-- back to 'session' (`PracticeContentKind(rawValue:) ?? .session`), which would
-- silently re-credit another creator. **Retiring a future library is only this
-- easy while the table is empty of it.** Check before copying this migration:
--
--     select content_kind, count(*)
--       from public.practice_plays
--      group by content_kind;
--
-- If that returns any 'massage' rows, STOP — do not force it. Keep the case in
-- Swift and leave the constraint alone; a section with no screen is handled by
-- making the routing side optional, not by dropping the ledger's vocabulary.
--
-- Failure mode if you skip that check: `add constraint` validates every existing
-- row, so this migration ERRORS OUT rather than deleting or corrupting anything.
-- A loud failure, not a quiet one — but read it as the signal above, not as a
-- constraint to work around.

alter table public.practice_plays
    drop constraint if exists practice_plays_content_kind_check;

-- Re-added with an explicit name. 0008 declared this inline on the column, so
-- Postgres auto-named it `practice_plays_content_kind_check`; naming it here
-- means the next migration to touch it can drop it by name without guessing.
alter table public.practice_plays
    add constraint practice_plays_content_kind_check
    check (content_kind in ('session', 'journal', 'exercise', 'recipe'));

-- `category` is untouched: 'somatic' stays a valid value. Only the section's
-- display title changed ("Somatic Therapy" → "Somatic Exercises"); the raw
-- value is still the contract with `practice_sessions.category`.
