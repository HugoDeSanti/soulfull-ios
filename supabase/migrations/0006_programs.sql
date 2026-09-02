-- 0006_programs.sql
-- "Digital Retreats" — the multi-day guided programs shelf on Home.
--
-- Until this table has rows, `HomeViewModel.programs` stays empty and the shelf
-- hides itself entirely. There is deliberately NO mock fallback: an invented
-- catalogue of programs nobody can enrol in is filler, and filler is what App
-- Review rejects. Seeding rows makes the shelf appear with no app release.
--
-- NOTE: the shelf is informational in v1 — there is no program detail screen,
-- so the cards don't push anywhere. Build that before promoting programs as a
-- headline feature.
--
-- How to apply: Supabase dashboard → SQL Editor, or `supabase db push`.

create table if not exists public.programs (
    id         text        primary key,      -- slug, e.g. 'nervous-system-healing'
    title      text        not null,
    lead       text        not null,         -- the guide's name
    date_range text        not null,         -- display string, e.g. 'Starts 12 Oct'
    days       integer     not null check (days > 0),
    -- Asset-catalog name today (e.g. 'practice-meditation'); a Storage URL later.
    image_url  text        not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.programs enable row level security;

-- Catalog content: readable by everyone, writable only via the dashboard or
-- the service role.
--
-- `to anon, authenticated` — the trap from 0003_retreats_public_read.sql.
-- Anonymous guests carry `role: authenticated` (with `is_anonymous: true`), so
-- a policy scoped to `anon` alone returns zero rows for every real user.
drop policy if exists "Programs are publicly readable" on public.programs;
create policy "Programs are publicly readable"
    on public.programs
    for select
    to anon, authenticated
    using (true);

-- Reuse the generic updated_at bumper defined in 0001_profiles.sql.
drop trigger if exists programs_set_updated_at on public.programs;
create trigger programs_set_updated_at
    before update on public.programs
    for each row execute function public.handle_profile_updated_at();

-- ---------------------------------------------------------------------------
-- Seeding example:
--
--   insert into public.programs (id, title, lead, date_range, days, image_url)
--   values ('nervous-system-healing', 'Nervous System Healing',
--           'Dr. Anya Iyer', 'Starts 12 Oct', 7, 'practice-somatic');
--
-- `SupabaseService.fetchPrograms()` orders by title and caches for 5 minutes.
-- ---------------------------------------------------------------------------
