-- 0027_guide_name_from_account.sql
-- A guide linked to a member account is called what the account is called,
-- and nothing else. The name lives on the account (`profiles.full_name`);
-- `instructors.name` becomes a copy kept by trigger, the way 0019 made `lead`
-- a copy of the guide's name. Three parts:
--
--   1. Empty profile names are filled from the name given at sign-up.
--   2. A linked guide's name is set from their account and can't be edited
--      apart from it; renaming the account renames the guide (and, through
--      0019's triggers, the `lead` on their sessions and digital retreats).
--   3. The propagation trigger fires on any update, not just `update of name`.
--
-- Why 1: on 2026-10-07 both member rows had `full_name = ''`. Each was made
-- before guests stopped getting a profile row (0023): `handle_new_user` copies
-- the sign-up name, but `on conflict do nothing` kept the guest's empty row,
-- and every later push from the app failed until 0024. The name was still on
-- the auth user (`raw_user_meta_data.full_name`, written by `createAccount`
-- and by Apple's first sign-in), so the server already knew it. Filling the
-- row also means the Community feed shows these members by name ("First L.")
-- rather than "A member", which is what the feed always intended.
--
-- Why 3: an `after update of name` trigger fires only when the UPDATE
-- statement names the column. A BEFORE trigger changing `name` (part 2, when
-- a guide is linked) doesn't count, so the guide would be renamed and every
-- `lead` left on the old name.
--
-- Decisions (2026-10-07, the owner: "names should only live in one place, so
-- that a person cannot have a different name as a guide than in their
-- regular account"):
--
--   * The account wins. Linking a guide replaces the name the team typed;
--     editing a linked guide's name in the dashboard is reverted. Rename the
--     member instead (their profile).
--   * An account with no name (none on the profile, none at sign-up) leaves
--     the guide's name as it is: a guide can't be nameless. It is replaced
--     the moment the account gets one.
--   * A guide's name is public (their profile, every practice they made),
--     while Community abbreviates members to "First L.". Linking a member to
--     a guide makes their full name public, which is what being a guide means.
--   * History doesn't move: `practice_plays.creator` stays the name the play
--     was made under, as before. Payouts follow `instructor_id` (0026).
--
-- APPLIED 2026-10-07 through the Management API, in one transaction with its
-- supabase_migrations.schema_migrations row (0027), after a dry run inside an
-- aborted transaction. The dry run: the two empty member names filled from
-- sign-up; the linked guide and Finding Ground's lead took the account's
-- name; a direct edit of the linked guide's name was reverted while an
-- unlinked guide's went through; the member renaming themselves as
-- `authenticated` renamed the guide and the lead; blanking the name left the
-- guide's last one; a session credited to the guide took the name as its
-- lead. Verified live after applying: 0 linked guides whose name differs from
-- their account's, 0 leads that differ from their guide's, all three new
-- triggers enabled, no client EXECUTE on either function. The same day the
-- owner's test account was renamed "Hugo Santi" (profile and sign-up
-- metadata) and every practice credited to its guide, alma-guerra; the guide
-- and every lead followed.

-- ---------------------------------------------------------------------------
-- 1. Empty profile names, from the name given at sign-up
-- ---------------------------------------------------------------------------

update public.profiles p
   set full_name = btrim(u.raw_user_meta_data ->> 'full_name')
  from auth.users u
 where u.id = p.id
   and not u.is_anonymous
   and coalesce(btrim(p.full_name), '') = ''
   and coalesce(btrim(u.raw_user_meta_data ->> 'full_name'), '') <> '';

-- ---------------------------------------------------------------------------
-- 2. A linked guide's name is their account's name
-- ---------------------------------------------------------------------------

-- SECURITY DEFINER: it reads the linked member's profile, which owner RLS
-- would hide from whoever is writing the guide row.
create or replace function public.instructor_name_from_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    account_name text;
begin
    if new.user_id is not null then
        select nullif(btrim(p.full_name), '') into account_name
          from public.profiles p
         where p.id = new.user_id;
        if account_name is not null then
            new.name := account_name;
        end if;
    end if;
    return new;
end;
$$;

revoke all on function public.instructor_name_from_account() from public, anon, authenticated;

drop trigger if exists instructors_name_from_account on public.instructors;
create trigger instructors_name_from_account
    before insert or update on public.instructors
    for each row execute function public.instructor_name_from_account();

-- The other direction: renaming the account renames the guide. SECURITY
-- DEFINER because a member renames themselves through their own profile and
-- has no write on `instructors`; it touches only the guide linked to the row
-- being written.
create or replace function public.guide_name_follows_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    account_name text := nullif(btrim(new.full_name), '');
begin
    if account_name is not null
       and (tg_op = 'INSERT' or new.full_name is distinct from old.full_name) then
        update public.instructors
           set name = account_name
         where user_id = new.id
           and name is distinct from account_name;
    end if;
    return null;
end;
$$;

revoke all on function public.guide_name_follows_account() from public, anon, authenticated;

drop trigger if exists profiles_guide_name on public.profiles;
create trigger profiles_guide_name
    after insert or update of full_name on public.profiles
    for each row execute function public.guide_name_follows_account();

comment on column public.instructors.name is
    'For a guide linked to a member account (user_id), a copy of that account''s '
    'profiles.full_name kept by trigger (0027): rename the member, not the guide. '
    'For an unlinked guide, the name the team gives them.';

-- ---------------------------------------------------------------------------
-- 3. Propagate on any rename, however it happened
-- ---------------------------------------------------------------------------
--
-- `propagate_instructor_name()` (0019) already compares old and new names,
-- so firing on every update costs a comparison.

drop trigger if exists instructors_propagate_name on public.instructors;
create trigger instructors_propagate_name
    after update on public.instructors
    for each row execute function public.propagate_instructor_name();

-- ---------------------------------------------------------------------------
-- Bring the guides already linked into line
-- ---------------------------------------------------------------------------

update public.instructors set user_id = user_id where user_id is not null;

-- ---------------------------------------------------------------------------
-- Verification (run each on its own)
-- ---------------------------------------------------------------------------
--
--   -- Every linked guide is called what their account is called:
--   select i.id, i.name, p.full_name from public.instructors i
--     join public.profiles p on p.id = i.user_id
--    where i.name is distinct from btrim(p.full_name) and btrim(p.full_name) <> '';   -- 0 rows
--
--   -- Every linked session and program carries that name as its lead:
--   select s.id, s.lead, i.name from public.practice_sessions s
--     join public.instructors i on i.id = s.instructor_id where s.lead <> i.name;     -- 0 rows
--   select pr.id, pr.lead, i.name from public.programs pr
--     join public.instructors i on i.id = pr.instructor_id where pr.lead <> i.name;   -- 0 rows
