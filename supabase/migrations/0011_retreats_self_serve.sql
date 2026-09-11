-- 0011_retreats_self_serve.sql
--
-- Makes adding a retreat a DATA change instead of an App Store release.
--
-- Two things stopped that before:
--
--   1. `image_url` did not hold a URL. It held an ASSET-CATALOG NAME
--      ("retreat-mallorca") that the app rendered with SwiftUI's
--      `Image(_ name:)` — a lookup inside the app bundle. A name that wasn't
--      compiled into the app drew nothing: no error, no placeholder, just a
--      blank photo area. So a new row could be inserted and simply look broken.
--
--   2. The long-form brochure (the "elements", their highlights, guides, the
--      testimonial, what's included) lived in Swift, in
--      `RetreatExperience.curated(for:)` — a switch statement with one case,
--      matched on the retreat's name. Any retreat that wasn't Mallorca got the
--      short fallback layout and there was no way to give it one from here.
--
-- After this migration a new retreat is: insert a row, upload a photo.

-- 1. The brochure, as a document.
--
-- jsonb rather than a retreat_experiences table: it is read whole, exactly
-- once, by exactly one screen, and it is deeply nested (elements ->
-- highlights, post_booking -> checkout -> line_items). Normalising it would be
-- six tables and a join for something that is never queried by its parts.
--
-- Keys inside are snake_case like everything else; the app decodes with
-- .convertFromSnakeCase. A malformed document does NOT break the catalog —
-- `RetreatRow.decodedExperience` logs it and falls back to the short layout.
alter table public.retreats
  add column if not exists experience jsonb;

comment on column public.retreats.experience is
  'Long-form brochure for the retreat detail screen: kind, date_range, '
  'cover_line, invitation[], who_for[], welcome, elements[], testimonial, '
  'guides[], stay, inclusions[], inclusions_note, and optional post_booking. '
  'snake_case keys. NULL means the retreat uses the concise fallback layout. '
  'Decoded by RetreatExperience in Models.swift — keep the two in step.';

-- 2. A public bucket for catalog photography.
--
-- Public on purpose. These are marketing images shown to anonymous guests, so
-- a signed URL buys nothing and costs plenty: a round trip before the first
-- pixel, no HTTP caching, and a signature that expires mid-scroll. Private
-- member media (practice-media) keeps its signing.
--
-- The app resolves "retreat-images/<file>" to this bucket's public URL, taking
-- the bucket from the first path segment — so a future bucket needs no release
-- either.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'retreat-images',
  'retreat-images',
  true,
  10485760,                                    -- 10MB; these are hero photographs, not raws
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Read for everyone.
--
-- ⚠️ Grant to BOTH anon AND authenticated. `signInAnonymously()` issues a real
-- JWT with role `authenticated` (is_anonymous: true), so a guest is NOT the
-- `anon` role — a policy scoped `to anon` alone returns nothing for every
-- single user of this app. This is the same trap 0003 was written to fix.
drop policy if exists "Retreat images are publicly readable" on storage.objects;
create policy "Retreat images are publicly readable"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'retreat-images');

-- Deliberately NO insert/update/delete policy: uploads go through the
-- dashboard or the service role. Nothing in the app writes images, so giving a
-- client role write access here would only ever be an attack surface.
