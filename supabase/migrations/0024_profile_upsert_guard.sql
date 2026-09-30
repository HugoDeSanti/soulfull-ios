-- 0024_profile_upsert_guard.sql
-- A member's profile upsert has failed since 0009, so no onboarding answers
-- have reached `profiles`. This lets it through without giving back what 0009
-- took away (a client choosing its own `email` or `stripe_customer_id`).
--
-- 0009's `protect_profile_server_columns` fills a client INSERT's `email` from
-- auth.users. It runs as the caller, and `authenticated` can't read auth.users,
-- so that branch raises 42501 "permission denied for table users".
-- `upsertProfile` is INSERT … ON CONFLICT DO UPDATE, and Postgres fires BEFORE
-- INSERT row triggers on the proposed row before it looks for a conflict, so
-- the upsert failed even though the member's row always existed.
-- `pushOnboardingAnswers` logs the error and moves on. On 2026-09-30 neither
-- live member had a name, intentions, a body state or a frequency on their
-- row, so Community showed both as "A member". Plain UPDATEs take the other
-- branch and always worked, which is why the avatar and sharing setters did.
-- Found by 0023's dry run, whose member-write check failed on it.
--
-- The email now comes from `caller_email()`, SECURITY DEFINER, which answers
-- the caller's own address and nobody else's (the caller's JWT already carries
-- it). That is the right address for any insert that gets through, because RLS
-- refuses a row whose id isn't the caller's. The guard itself stays SECURITY
-- INVOKER: it tells a client write from the server's by `current_user`, which
-- a definer function would replace with its owner.
--
-- The two members' answers are still only on their phones. The app pushes them
-- on account creation, and on an Apple sign-in to a row with no answers; an
-- email sign-in only pulls.
--
-- APPLIED 2026-09-30 with 0023 (see its header), after the same dry run: a
-- member's upsert went through with a smuggled email and stripe_customer_id
-- both ignored, and a first insert with no row yet took its email from
-- auth.users.

create or replace function public.caller_email()
returns text
language sql
security definer
set search_path = ''
stable
as $$
    select u.email::text from auth.users u where u.id = auth.uid()
$$;

-- The guard runs as the client, so the client role needs EXECUTE.
revoke all on function public.caller_email() from public, anon;
grant execute on function public.caller_email() to authenticated;

create or replace function public.protect_profile_server_columns()
returns trigger
language plpgsql
as $$
begin
    if current_user in ('anon', 'authenticated') then
        if tg_op = 'INSERT' then
            new.email              := public.caller_email();
            new.stripe_customer_id := null;
        else
            new.email              := old.email;
            new.stripe_customer_id := old.stripe_customer_id;
        end if;
    end if;
    return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Verification (each on its own)
-- ---------------------------------------------------------------------------
--
--   -- As a member (JWT sub = their id), the app's own upsert succeeds:
--   --   POST /rest/v1/profiles  Prefer: resolution=merge-duplicates
--   --   {id, full_name, intentions, body_state, frequency} → 201
--   -- …and a smuggled email or stripe_customer_id is ignored:
--   --   the same with {"email": "x@example.com"} → the row keeps the auth email.
--   -- A client insert for someone else's id → 403 (42501, RLS).
