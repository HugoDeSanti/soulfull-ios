-- 0005_practice_sessions.sql
-- The Practice tab's audio/video tracks (Somatic / Breathwork / Meditation).
--
-- Until this table has rows, `PracticeView` renders those three cards as
-- "Coming soon" and they are not tappable. `SupabaseService.availablePracticeCategories()`
-- checks which categories have content, so seeding rows lights the tracks up
-- with NO app release — the client re-checks on every visit to the tab
-- (5-minute cache).
--
-- How to apply: Supabase dashboard → SQL Editor, or `supabase db push`.

create table if not exists public.practice_sessions (
    id               bigint      generated always as identity primary key,
    category         text        not null check (category in ('somatic', 'breathwork', 'meditation')),
    title            text        not null,
    lead             text        not null,
    media_kind       text        not null check (media_kind in ('audio', 'video')),
    -- Bucket-relative path inside the `practice-media` Storage bucket, e.g.
    -- 'somatic/grounding-body-scan.m4a'. The app signs it via
    -- SupabaseService.signedMediaURL. An absolute http(s) URL also plays, but
    -- prefer Storage so the media stays private.
    storage_path     text        not null,
    duration_seconds integer     not null check (duration_seconds > 0),
    -- Asset-catalog name today (e.g. 'retreat-sedona'); a Storage URL later.
    image_url        text        not null,
    blurb            text,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now()
);

create index if not exists practice_sessions_category_idx
    on public.practice_sessions (category);

alter table public.practice_sessions enable row level security;

-- Catalog content: readable by everyone, writable only via the dashboard or
-- the service role.
--
-- NOTE the `to anon, authenticated` — this is the trap documented in
-- 0003_retreats_public_read.sql. Anonymous guests carry `role: authenticated`
-- (with `is_anonymous: true`), NOT the `anon` role, so a policy scoped to
-- `anon` alone returns zero rows for every real user of this app.
drop policy if exists "Practice sessions are publicly readable" on public.practice_sessions;
create policy "Practice sessions are publicly readable"
    on public.practice_sessions
    for select
    to anon, authenticated
    using (true);

-- Reuse the generic updated_at bumper defined in 0001_profiles.sql.
drop trigger if exists practice_sessions_set_updated_at on public.practice_sessions;
create trigger practice_sessions_set_updated_at
    before update on public.practice_sessions
    for each row execute function public.handle_profile_updated_at();


-- ---------------------------------------------------------------------------
-- Storage bucket for the media itself.
--
-- Private: the app mints a 1-hour signed URL per playback
-- (SupabaseService.signedMediaURL). Do NOT make this public — the audio and
-- video are the product.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('practice-media', 'practice-media', false)
on conflict (id) do nothing;

-- Anyone signed in (including anonymous guests) may read objects; nobody
-- writes from the client.
drop policy if exists "Practice media is readable by app users" on storage.objects;
create policy "Practice media is readable by app users"
    on storage.objects
    for select
    to anon, authenticated
    using (bucket_id = 'practice-media');


-- ---------------------------------------------------------------------------
-- Seeding
--
-- 1. Upload the files (dashboard → Storage → practice-media, or the CLI):
--        supabase storage cp ./grounding-body-scan.m4a \
--            ss:///practice-media/somatic/grounding-body-scan.m4a
--
-- 2. Insert a row per session, with storage_path matching the upload:
--
--    insert into public.practice_sessions
--        (category, title, lead, media_kind, storage_path, duration_seconds, image_url, blurb)
--    values
--        ('somatic', 'Grounding Body Scan', 'Dr. Anya Iyer', 'audio',
--         'somatic/grounding-body-scan.m4a', 720, 'retreat-sedona',
--         'A slow head-to-toe scan to settle the nervous system.');
--
-- A category lights up in the app as soon as it has at least one row. Seed all
-- three, or seed one and leave the others reading "Coming soon" — both are
-- handled.
-- ---------------------------------------------------------------------------
