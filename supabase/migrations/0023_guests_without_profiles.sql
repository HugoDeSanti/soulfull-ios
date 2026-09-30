-- 0023_guests_without_profiles.sql
-- A profile row is for a member. An anonymous guest gets none, and a guest who
-- goes quiet for 30 days is deleted.
--
-- Every launch without an account opens an anonymous session (AuthManager),
-- and until now `handle_new_user` (0001) gave each one a profile: a blank row
-- per install, per simulator run and per sign-out, with a NULL email because a
-- guest has none. Nothing reads a guest's row (the You tab, the onboarding push
-- and the Community views are all members-only), and a guest owns nothing else
-- either: browsing is free and every personal action is behind the account
-- gate. On 2026-09-30 the project held 25 guests and 2 members; all 25
-- NULL-email profiles were guests, every one blank, and no guest had a play,
-- an enrolment, a follow or a device token.
--
--   1. `handle_new_user` skips anonymous users, and the same function runs
--      again when a guest's account becomes permanent: the email/password
--      upgrade keeps the user id and flips `is_anonymous` off once the address
--      is confirmed. Apple sign-in and a plain sign-up create a permanent user
--      outright, which the insert trigger already covers.
--   2. The profiles insert and update policies refuse guests.
--   3. The existing guest profiles are deleted.
--   4. `purge_idle_guests()` deletes anonymous users idle for 30 days, nightly
--      through pg_cron (enabled here).
--
-- APPLIED 2026-09-30 through the Management API together with 0024, and
-- recorded in supabase_migrations.schema_migrations, after a dry run inside an
-- aborted transaction. The dry run showed: a new guest gets no row; the
-- upgrade creates one carrying the email and name; a sign-up creates one; a
-- guest's own insert is refused (42501, RLS); a member whose token still
-- claims anonymous can upsert (with 0024); nobody can insert another's row;
-- neither client role can execute the purge, which took a 60-day test guest
-- and no member (7 live guests were idle at the time). Live afterwards: the
-- 25 guest profiles were gone and the 2 members' kept; a real anonymous
-- sign-in through GoTrue created no row, its POST /rest/v1/profiles answered
-- 403 (42501), and it still read the catalog (200). The test guest was deleted.
--
-- Decisions (2026-09-30):
--
--   * The anonymous SESSION stays. The Community feed, presence counts and a
--     guide's page are open to a guest, and they read views and RPCs granted
--     to `authenticated` only (community_activity, community_members,
--     practice_presence, program_presence, instructor_social). Serving them to
--     `anon` instead would mean re-granting owner-rights views whose grants
--     are their only protection.
--   * The guest check reads `auth.users`, not the JWT's `is_anonymous` claim
--     (which 0019 uses for follows). Right after a confirmation the access
--     token can still say anonymous (with "Confirm email" off, PUT /user
--     upgrades the user and issues no new token at all), and
--     `pushOnboardingAnswers` writes in exactly that window. The claim would
--     refuse a new member's answers; the row can't be stale.
--   * "Idle" is the latest of the user's creation, last update, last sign-in
--     and last session refresh. `last_sign_in_at` alone misses a guest who has
--     been refreshing one session for months (one live guest signed in in June
--     and refreshed in September). 30 days is far past an unanswered
--     confirmation email's life, so a half-finished upgrade isn't cut short.
--   * Deleting a guest costs its owner nothing. At launch a session that can't
--     be restored falls through to a fresh anonymous sign-in
--     (`AuthManager.initialize`), the same new guest id signing out gives. The
--     purge takes only users that are anonymous AND have no email, so it can
--     never reach an address.

-- ---------------------------------------------------------------------------
-- 1. A profile for members only
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    -- A guest has nothing to put in a profile. `on_auth_user_made_permanent`
    -- calls this again when they become a member.
    if new.is_anonymous then
        return new;
    end if;

    insert into public.profiles (id, email, full_name)
    values (
        new.id,
        new.email,
        coalesce(new.raw_user_meta_data ->> 'full_name', '')
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

-- The upgrade is an UPDATE, not an insert. `on_auth_user_email_changed` (0009)
-- may fire on the same statement, in either order: this insert copies the
-- email itself, and that sync is a no-op until the row exists.
drop trigger if exists on_auth_user_made_permanent on auth.users;
create trigger on_auth_user_made_permanent
    after update of is_anonymous on auth.users
    for each row
    when (old.is_anonymous and not new.is_anonymous)
    execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 2. Guests can't write a profile
-- ---------------------------------------------------------------------------

-- Whether the caller is a member, from `auth.users` rather than the token (see
-- Decisions). SECURITY DEFINER because a client role can't read auth.users; it
-- answers one boolean about the caller and nobody else.
create or replace function public.caller_has_account()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
    select exists (
        select 1 from auth.users u
        where u.id = auth.uid()
          and not u.is_anonymous
    )
$$;

revoke all on function public.caller_has_account() from public, anon;
grant execute on function public.caller_has_account() to authenticated;

-- `upsertProfile` is INSERT … ON CONFLICT DO UPDATE, which checks the insert
-- policy even when the row exists, so both policies carry the check.
drop policy if exists "Users can insert their own profile" on public.profiles;
create policy "Users can insert their own profile"
    on public.profiles
    for insert
    to authenticated
    with check (auth.uid() = id and public.caller_has_account());

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
    on public.profiles
    for update
    to authenticated
    using (auth.uid() = id)
    with check (auth.uid() = id and public.caller_has_account());

-- ---------------------------------------------------------------------------
-- 3. The guest profiles already there
-- ---------------------------------------------------------------------------
--
-- Nothing references `profiles` by foreign key (member tables point at
-- auth.users), so this touches no other table.

delete from public.profiles p
 using auth.users u
 where u.id = p.id
   and u.is_anonymous;

-- ---------------------------------------------------------------------------
-- 4. Idle guests, deleted nightly
-- ---------------------------------------------------------------------------

create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

-- Returns how many it deleted. Deleting the auth user cascades to its
-- sessions and identities (and to a profile, were there one).
create or replace function public.purge_idle_guests(idle interval default interval '30 days')
returns integer
language plpgsql
set search_path = ''
as $$
declare
    purged integer;
begin
    delete from auth.users u
     where u.is_anonymous
       and u.email is null
       and greatest(
               u.created_at,
               u.updated_at,
               u.last_sign_in_at,
               (select max(s.updated_at) from auth.sessions s where s.user_id = u.id)
           ) < now() - idle;
    get diagnostics purged = row_count;
    return purged;
end;
$$;

-- Server-only: pg_cron runs it as postgres. Supabase grants EXECUTE on a new
-- function to both client roles by default, so they are named here.
revoke all on function public.purge_idle_guests(interval) from public, anon, authenticated;

-- Scheduling an existing job name replaces it, so a re-run is harmless.
select cron.schedule(
    'purge-idle-guests',
    '17 3 * * *',
    $$select public.purge_idle_guests()$$
);

-- ---------------------------------------------------------------------------
-- Verification (each on its own)
-- ---------------------------------------------------------------------------
--
--   -- No guest has a profile:
--   select count(*) from profiles p join auth.users u on u.id = p.id where u.is_anonymous;  -- 0
--   -- The job, and how its runs went:
--   select jobname, schedule, command, active from cron.job where jobname = 'purge-idle-guests';
--   select status, return_message, start_time from cron.job_run_details
--    where jobid = (select jobid from cron.job where jobname = 'purge-idle-guests')
--    order by start_time desc limit 5;
--   -- Who the next run would take (dry):
--   select count(*) from auth.users u where u.is_anonymous and u.email is null
--      and greatest(u.created_at, u.updated_at, u.last_sign_in_at,
--          (select max(s.updated_at) from auth.sessions s where s.user_id = u.id))
--          < now() - interval '30 days';
--   -- As a guest: POST /rest/v1/profiles {id: <own id>} → 403 (42501).
