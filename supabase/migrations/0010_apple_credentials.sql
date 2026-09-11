-- 0010_apple_credentials.sql
--
-- Storage for the Sign in with Apple refresh token that `delete-account` needs
-- in order to call Apple's /auth/revoke.
--
-- WHY: App Store Guideline 5.1.1(v) — "If your app offers Sign in with Apple,
-- you must use the Sign in with Apple REST API to revoke the user tokens when
-- the account is deleted." Deleting the Supabase auth user does not do that;
-- without the revoke call the app keeps showing up under Settings -> Apple ID
-- -> Sign in with Apple after the user deletes their account, which is exactly
-- what App Review checks. Revoking needs a refresh token, the refresh token
-- comes from exchanging an authorization code, and the code expires in about
-- five minutes — so it has to be exchanged at sign-in and the result kept here.
--
-- Written by:  `store-apple-token` (service role), on every Apple sign-in.
-- Read by:     `delete-account` (service role), immediately before deletion.
-- Read by a client: NEVER. See the lockdown below.

create table if not exists public.apple_credentials (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  -- Apple's long-lived refresh token. Its only use is /auth/revoke; it is
  -- never returned to a client and never leaves an Edge Function.
  refresh_token text        not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.apple_credentials is
  'Sign in with Apple refresh tokens, used solely to revoke the Apple grant on '
  'account deletion (App Store Guideline 5.1.1(v)). Service role only — no '
  'client role may read or write this table.';

-- Two independent locks, on purpose, because this table holds a credential.
--
-- 1. RLS on with ZERO policies: every client role is denied by default. The
--    service role bypasses RLS, so the two Edge Functions still work.
alter table public.apple_credentials enable row level security;

-- 2. Grants revoked outright on THIS table. This is the lock that survives
--    someone later adding a well-meaning policy to it.
--
--    Scoped to this table on purpose: `alter default privileges … in schema
--    public` would silently change the grants every FUTURE table gets, and the
--    catalog tables (retreats/programs/practice_sessions) depend on the normal
--    ones. Locking one table must not reshape the schema's defaults.
revoke all on public.apple_credentials from anon, authenticated;

-- Deliberately NO delete policy and no cleanup job: the row's lifetime is the
-- user's. `on delete cascade` above removes it when the auth user goes, which
-- happens only after `delete-account` has read the token and called revoke.
