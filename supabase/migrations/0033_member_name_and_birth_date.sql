-- 0033_member_name_and_birth_date.sql
-- A member's name in two parts (`profiles.first_name` and `last_name`), and
-- their date of birth (`profiles.date_of_birth`).
--
-- Sign-up asked for one "Your name" line, and everything that needed a part of
-- it guessed by splitting on spaces: Community's "First L." took the first
-- word and the second word's initial, so "Mary Ann Smith" showed as "Mary A.".
-- From 1.0 (20) the app asks for a first and a last name and writes them as
-- such. The parts are where the name lives now.
--
--   1. `full_name` stays, as a copy the server keeps: first, a space, last.
--      Everything that reads it is unchanged: search, the guide named by their
--      account (0027), Stripe, report emails, the 64-character limit (0030).
--      `profiles_name_parts` holds the copy to the parts.
--   2. One trigger owns all three columns (`bound_profile_name`, 0030's, now
--      firing on the parts too). A write in parts sets the line. A write of the
--      line alone, from a build up to 1.0 (19), a sign-up made on one, or a
--      hand edit in the SQL editor, is split at the first space, the old rule.
--      A last name alone becomes the first (the name they go by). Together
--      they are cut to 64 as 0030 cut the line: the first name first, then
--      what is left of the last, so the copy always fits.
--   3. 0027's `profiles_guide_name` fired on `update of full_name`, which
--      counts only columns named in the UPDATE, not ones a trigger changed. An
--      update of the parts alone would have left a linked guide on the old
--      name, so it now fires on all three.
--   4. `handle_new_user` copies `first_name` / `last_name` from the sign-up
--      metadata (the app sends both, and `full_name` for older readers), and
--      falls back to `full_name` (an older build's sign-up) through the split.
--   5. Community shows the first name and the last name's initial, uppercased:
--      "Mary Ann S.", "Hugo D." (`community_display_name(first, last)`).
--      `community_members` and `search_members` call it, with the same
--      columns and signature as before, so nothing that joins them changes.
--      The one-argument form stays for `send-like-push` v2, which calls it by
--      RPC with the line, until v3 sends the parts.
--
-- Existing rows are split by the old rule (first word / the rest), which is
-- what the feed already showed. A member corrects theirs from the You tab.
--
--   6. `date_of_birth` (a `date`, null until given): asked at email sign-up
--      and offered on the You tab, never after Sign in with Apple (asking for
--      more after Apple is a rejection pattern). Private like the rest of the
--      row: owner RLS, and no view or function hands it to anyone else. A
--      member is at least 13 (the Terms' minimum age, and the App Store's
--      13+), so a client write younger than that, or before 1900, is refused
--      (22008); the app's wheel can't reach either. The server's day is UTC,
--      so the bound gives a day's grace to a member whose day is ahead.
--      `handle_new_user` copies the sign-up metadata's `date_of_birth` only
--      when it is a plausible day, so a bad one can never fail a sign-up.
--
-- How to apply: Management API (one transaction with its schema_migrations
-- row) or `supabase db push`. Safe to re-run.
--
-- APPLIED to the live project 2026-10-12 through the Management API, in one
-- transaction with its schema_migrations row (0033), after two dry runs inside
-- aborted transactions. The first caught `is_member_birth_date` revoked from
-- `authenticated`: the birth-date trigger runs as the writer and fires on
-- every insert, so every member's profile upsert failed (42501). The second,
-- as the owner's test account (linked to `alma-guerra`): parts → line
-- "Mary Ann Smith", the guide renamed with it, Community "Mary Ann S."; the
-- same line upserted again by an older build → parts kept; a different line
-- → "Hugo" / "De Santiago"; this app's first-name-only upsert → the last name
-- kept; 40 + 40 → 40 / 23 / 64; a date 12 years ago → 22008, 1990-05-01
-- stored; `community_members` still id / display_name / avatar_url; a
-- sign-up with parts and a date → both copied, an older build's line with an
-- under-13 date → split, no date. After applying: the three columns, the
-- `profiles_birth_date` / `profiles_bound_name` / `profiles_guide_name`
-- triggers and `profiles_name_parts` in place; every row's line equal to its
-- parts and none named without a first name (5 rows); every linked guide
-- still named by their account; `community_members` and `search_members`
-- name from the parts; anon has no SELECT on the view and authenticated no
-- UPDATE.


-- ===========================================================================
-- 1. The columns
-- ===========================================================================

alter table public.profiles
    add column if not exists first_name    text not null default '',
    add column if not exists last_name     text not null default '',
    add column if not exists date_of_birth date;

comment on column public.profiles.first_name is
    'The name the member goes by. Home greets them by it; Community shows it with the last initial (0033).';
comment on column public.profiles.last_name is
    'The member''s last name. Others see only its initial (0033).';
comment on column public.profiles.full_name is
    'first_name, a space, last_name: kept by trigger (0033). A write of this alone is split at the first space.';
comment on column public.profiles.date_of_birth is
    'Given at email sign-up or on the You tab; at least 13 years ago. Private: never shown to other members (0033).';


-- ===========================================================================
-- 2. One trigger for the three
-- ===========================================================================

create or replace function public.bound_profile_name()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    ws constant text := E' \t\r\n';
    from_line boolean;
    split text[];
begin
    -- Parts win whenever they were written. Otherwise a new line is split.
    if tg_op = 'INSERT' then
        from_line := btrim(coalesce(new.first_name, ''), ws) = ''
                 and btrim(coalesce(new.last_name, ''), ws) = '';
    else
        from_line := new.first_name is not distinct from old.first_name
                 and new.last_name  is not distinct from old.last_name
                 and new.full_name  is distinct from old.full_name;
    end if;

    if from_line then
        split := regexp_match(btrim(coalesce(new.full_name, ''), ws), '^(\S+)\s*(.*)$');
        new.first_name := coalesce(split[1], '');
        new.last_name  := coalesce(split[2], '');
    end if;

    new.first_name := btrim(coalesce(new.first_name, ''), ws);
    new.last_name  := btrim(coalesce(new.last_name, ''), ws);

    -- A last name alone is the name they go by.
    if new.first_name = '' then
        new.first_name := new.last_name;
        new.last_name  := '';
    end if;

    -- 64 together (0030): the first name first, then what's left of the last.
    new.first_name := btrim(left(new.first_name, 64), ws);
    new.last_name  := btrim(left(new.last_name, greatest(64 - char_length(new.first_name) - 1, 0)), ws);
    new.full_name  := btrim(new.first_name || ' ' || new.last_name, ws);
    return new;
end;
$$;

revoke all on function public.bound_profile_name() from public, anon, authenticated;

drop trigger if exists profiles_bound_name on public.profiles;
create trigger profiles_bound_name
    before insert or update of first_name, last_name, full_name on public.profiles
    for each row execute function public.bound_profile_name();

-- 0027's function is unchanged: it compares `full_name`, which the trigger
-- above has set by the time this runs.
drop trigger if exists profiles_guide_name on public.profiles;
create trigger profiles_guide_name
    after insert or update of first_name, last_name, full_name on public.profiles
    for each row execute function public.guide_name_follows_account();


-- ===========================================================================
-- 3. Every row in parts
-- ===========================================================================
--
-- Split by the old rule. Setting the parts runs the trigger, which writes the
-- line back from them (one space between first and last, whatever was there),
-- and a linked guide follows. A row with no name gets '' throughout.

update public.profiles
   set first_name = coalesce((regexp_match(btrim(coalesce(full_name, ''), E' \t\r\n'), '^(\S+)\s*(.*)$'))[1], ''),
       last_name  = coalesce((regexp_match(btrim(coalesce(full_name, ''), E' \t\r\n'), '^(\S+)\s*(.*)$'))[2], '');

alter table public.profiles drop constraint if exists profiles_name_parts;
alter table public.profiles
    add constraint profiles_name_parts
    check (full_name is null or full_name = btrim(first_name || ' ' || last_name, E' \t\r\n'));


-- ===========================================================================
-- 4. Date of birth
-- ===========================================================================

-- A day someone can have been born on and be a member: 1900 or later, and at
-- least 13 years ago. `today` is the member's own day at its most generous:
-- UTC + 1, since no time zone is further ahead than a day.
create or replace function public.is_member_birth_date(d date)
returns boolean
language sql
stable
set search_path = ''
as $$
    select d >= date '1900-01-01'
       and d <= ((current_date + 1) - interval '13 years')::date
$$;

-- The sign-up metadata's `yyyy-MM-dd`, or null for anything else.
create or replace function public.member_birth_date(raw text)
returns date
language plpgsql
stable
set search_path = ''
as $$
declare
    d date;
begin
    if raw is null or raw !~ '^\d{4}-\d{2}-\d{2}$' then
        return null;
    end if;
    d := raw::date;
    return case when public.is_member_birth_date(d) then d end;
exception when others then
    return null;
end;
$$;

create or replace function public.check_profile_birth_date()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.date_of_birth is not null and not public.is_member_birth_date(new.date_of_birth) then
        raise exception 'date_of_birth_out_of_range' using errcode = '22008';
    end if;
    return new;
end;
$$;

-- `check_profile_birth_date` runs as whoever writes the row, and every
-- profile INSERT fires it (an upsert's insert branch included), so the roles
-- that write profiles must be able to call this. The dry run caught it
-- revoked: every member's upsert failed with 42501.
revoke all on function public.is_member_birth_date(date) from public, anon;
grant execute on function public.is_member_birth_date(date) to authenticated, service_role;
revoke all on function public.member_birth_date(text) from public, anon, authenticated;
revoke all on function public.check_profile_birth_date() from public, anon, authenticated;

drop trigger if exists profiles_birth_date on public.profiles;
create trigger profiles_birth_date
    before insert or update of date_of_birth on public.profiles
    for each row execute function public.check_profile_birth_date();


-- ===========================================================================
-- 5. Sign-up
-- ===========================================================================
--
-- 0023's function, with the parts and the date of birth. A sign-up from a
-- build up to 1.0 (19) carries only `full_name`, which the trigger splits.

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

    insert into public.profiles (id, email, first_name, last_name, full_name, date_of_birth)
    values (
        new.id,
        new.email,
        coalesce(new.raw_user_meta_data ->> 'first_name', ''),
        coalesce(new.raw_user_meta_data ->> 'last_name', ''),
        coalesce(new.raw_user_meta_data ->> 'full_name', ''),
        public.member_birth_date(new.raw_user_meta_data ->> 'date_of_birth')
    )
    on conflict (id) do nothing;
    return new;
end;
$$;


-- ===========================================================================
-- 6. How Community shows a name
-- ===========================================================================

create or replace function public.community_display_name(first_name text, last_name text)
returns text
language sql
immutable
as $$
    select case
        when btrim(coalesce(first_name, '')) = '' then 'A member'
        when public.is_objectionable_name(coalesce(first_name, '') || ' ' || coalesce(last_name, ''))
            then 'A member'
        when btrim(coalesce(last_name, '')) = '' then btrim(first_name)
        else btrim(first_name) || ' ' || upper(left(btrim(last_name), 1)) || '.'
    end
$$;

-- 0029's view, named from the parts. Same columns, so `community_activity`,
-- `member_notifications`, presence, `instructor_social()` and the comment
-- thread keep working unchanged.
create or replace view public.community_members as
select
    p.id,
    public.community_display_name(p.first_name, p.last_name) as display_name,
    p.avatar_url
from public.profiles p
where p.email is not null and p.email <> ''
  and not exists (
      select 1 from public.member_blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = auth.uid())
  )
  and (
      (select public.caller_has_account())
      or (p.share_activity and exists (
          select 1 from public.practice_plays pl
          where pl.user_id = p.id
            and pl.completed
            and pl.completed_at > now() - interval '30 days'
            and pl.content_kind <> 'journal'
      ))
  );

-- Restated (create or replace keeps grants, but this view was once updatable
-- through: keep the revoke next to it).
revoke all on public.community_members from anon, authenticated, public;
grant select on public.community_members to authenticated;

-- 0028's search, named from the parts. It still matches on the whole line, so
-- "Mary Ann", "Smith" and "Ann Smith" all find her.
create or replace function public.search_members(q text)
returns table (id uuid, display_name text, avatar_url text)
language sql
security definer
set search_path = public
stable
as $$
    select p.id,
           public.community_display_name(p.first_name, p.last_name) as display_name,
           p.avatar_url
    from public.profiles p
    where auth.uid() is not null
      and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true
      and length(btrim(q)) >= 2
      and p.id <> auth.uid()
      and p.email is not null and p.email <> ''
      and p.full_name is not null
      and p.full_name ilike '%' || replace(replace(replace(btrim(q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
      and not exists (
          select 1 from public.member_blocks b
          where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
             or (b.blocker_id = p.id and b.blocked_id = auth.uid())
      )
    order by p.full_name
    limit 20
$$;

revoke all on function public.search_members(text) from public, anon;
grant execute on function public.search_members(text) to authenticated;


-- ---------------------------------------------------------------------------
-- Verification (run each on its own)
-- ---------------------------------------------------------------------------
--
--   -- Every row's line is its parts:
--   select id, first_name, last_name, full_name from public.profiles
--    where full_name is distinct from btrim(first_name || ' ' || last_name);         -- 0 rows
--
--   -- Every linked guide still carries their account's name (0027):
--   select i.id, i.name, p.full_name from public.instructors i
--     join public.profiles p on p.id = i.user_id
--    where i.name is distinct from p.full_name and p.full_name <> '';                -- 0 rows
--
--   select public.community_display_name('Mary Ann', 'Smith');      -- Mary Ann S.
--   select public.community_display_name('Hugo', 'de Santiago');    -- Hugo D.
--   select public.community_display_name('Mara', '');               -- Mara
--   select public.community_display_name('', '');                   -- A member
--   select public.community_display_name('Soulfull', 'Team');       -- A member
--
--   Inside an aborted transaction, as a member:
--     update profiles set first_name = 'Mary Ann', last_name = 'Smith' where id = auth.uid();
--       → full_name 'Mary Ann Smith'; a linked guide renamed with it
--     update profiles set full_name = 'Hugo De Santiago' where id = auth.uid();   (a 1.0 (19) write)
--       → 'Hugo' / 'De Santiago'
--     update profiles set first_name = repeat('a', 40), last_name = repeat('b', 40) where id = auth.uid();
--       → 40 a's / 23 b's, full_name 64
--     the same name upserted again → parts unchanged (an older build re-pushing
--       its line never re-splits a name written in parts)
--     update profiles set date_of_birth = current_date - interval '12 years' … → 22008
--     update profiles set date_of_birth = '1990-05-01' …                         → stored
--   select public.member_birth_date('1990-05-01');   -- 1990-05-01
--   select public.member_birth_date('2020-01-01');   -- null (under 13)
--   select public.member_birth_date('1990-02-30');   -- null
--   select public.member_birth_date('soon');         -- null
