-- 0003_retreats_public_read.sql
-- Fix: retreats returned 0 rows once anonymous sign-ins were enabled.
--
-- Enabling anonymous auth switched the app's requests from the `anon` Postgres
-- role (API key only) to the `authenticated` role — anonymous users carry
-- `role: authenticated` (with `is_anonymous: true`) in their JWT. The existing
-- retreats SELECT policy only covered `anon`, so authenticated reads saw nothing.
--
-- Retreats are public catalog content, so make them readable by both the
-- anonymous (`anon`) and signed-in (`authenticated`) client roles. Permissive
-- policies are OR'd, so this is additive and safe alongside any existing policy.
--
-- NOTE for future tables: `programs` and `practice_sessions` don't exist yet
-- (the app uses mock data). When you create them, give them the same
-- `to anon, authenticated` SELECT policy or reads will break the same way.

alter table public.retreats enable row level security;

drop policy if exists "Retreats are publicly readable" on public.retreats;
create policy "Retreats are publicly readable"
    on public.retreats
    for select
    to anon, authenticated
    using (true);
