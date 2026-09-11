# Adding a retreat

**No app release required.** A retreat is a row in `retreats` plus a photo in
Storage. Both are things you do in the Supabase dashboard.

This was not true before 2026-09-11: `image_url` held an *asset-catalog name*
compiled into the app, and the long-form brochure lived in Swift
(`RetreatExperience.curated(for:)` — a switch statement with one case, matched
on the retreat's name). Adding a retreat meant shipping a build. Both are now
data. See `supabase/migrations/0011_retreats_self_serve.sql`.

---

## 1. Upload the photograph

Dashboard → **Storage** → `retreat-images` → Upload.

- **Bucket:** `retreat-images` (public, 10MB cap, JPEG/PNG/WebP only)
- **Naming:** anything; `mallorca-2027.jpg` reads well
- **Size:** it is used full-bleed behind type on the detail hero and the
  retreats stack. ~2000px on the long edge is plenty; bigger only costs the
  user bandwidth.
- **Tone:** the app lays cream type over the top of it. A photo that is bright
  and busy in its upper third will fight the header — `PhotoBackdrop` darkens
  the top band, but it can't rescue a white sky.

## 2. Insert the row

```sql
insert into public.retreats
  (name, country, start_date, end_date, max_guests, price_usd,
   tags, blurb, image_url, tone_top, tone_mid, tone_base)
values (
  'Patagonia',
  'Chile',
  '2028-03-04',
  '2028-03-10',
  12,
  5200,
  array['Hiking', 'Cold Therapy', 'Stillness'],
  'Granite, wind, and long silences. Walk all day, sleep like the dead.',
  'retreat-images/patagonia-2028.jpg',      -- bucket/path, NOT an asset name
  '#B9C3CD', '#5C6B7A', '#161B21'           -- see "Tone colours" below
);
```

| Column | Notes |
|---|---|
| `start_date` | **Must be in the future.** The app filters `start_date > today` — a retreat that has begun can no longer be joined, so it drops out of the catalog. |
| `tags` | Not decoration. With no brochure these become the numbered "The days" list on the detail screen. |
| `blurb` | With no brochure this is the pull-quote. Write it to stand alone. |
| `image_url` | `bucket/path.jpg`. A bare name with no slash is treated as a **bundled asset** and will show the placeholder if it isn't in the app. |
| `tone_*` | Hex. Graded behind the retreat name in the stack — sample the photo: a light tone from the sky, a mid from the subject, a near-black base. |
| `group_chat_url` | Optional WhatsApp invite. Must be `https://` — other schemes are rejected at the decode boundary. |

The catalog caches for 5 minutes, so give it that or cold-start the app.

## 3. Add the brochure (optional)

Without one, the detail screen renders a complete concise layout from `blurb`
and `tags`. With one, it renders the full editorial spread.

```sql
update public.retreats set experience = '{
  "kind": "A Wellness & Fitness Retreat",
  "cover_line": "One line under the title on the cover.",
  "invitation": ["First stanza.", "Second stanza."],
  "who_for": ["A line.", "Another line."],
  "welcome": "The pull-quote under who-this-is-for.",
  "elements": [
    {
      "title": "Move",
      "system_image": "bicycle",
      "summary": "One line.",
      "highlights": ["A specific", "Another specific"]
    }
  ],
  "guides": [{ "name": "Alejandra Campos", "role": "Head Retreat Leader" }],
  "stay": "Where they sleep.",
  "inclusions": ["What is included"],
  "inclusions_note": "What is not."
}'::jsonb
where name = 'Patagonia';
```

**Keys are snake_case.** The app decodes with `.convertFromSnakeCase`, so
`system_image` → `systemImage`. Get a key wrong and that field goes missing, or
the whole document fails to decode.

Optional: `testimonial` (`quote`/`author`/`attribution`), `post_booking` (the
reserved-trip screens), and `date_range`.

### Two things to know

**`date_range` overrides the real dates — normally leave it out.** When absent
the cover line is derived from `start_date`/`end_date` and cannot drift. Set it
only when the brochure genuinely says something the dates don't ("Midsummer
week"), and remember it then wins over the row.

**A malformed document fails soft.** `RetreatRow.decodedExperience` catches the
decode error, logs it, and returns nil — the retreat falls back to the concise
layout rather than breaking the catalog. That is deliberate, and it means **a
broken brochure looks exactly like no brochure.** If a retreat you gave a
document to is rendering the short layout, the JSON didn't decode; the reason
is in the device log under the `data` category.

`system_image` values are SF Symbol names. An unknown one renders nothing —
check it in SF Symbols first.

---

## Verifying

Run the UI test that guards this end to end:

```bash
xcodebuild test -project SoulfullGatherings.xcodeproj -scheme SoulfullGatherings \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SoulfullUITests/RetreatBrochureTests
```

It opens Mallorca from the live database and asserts the brochure layout
rendered. It is pointed at Mallorca specifically, so it won't catch a problem
with *your* new row — for that, open the retreat in the app and look.

## What still needs a release

- The **four element icons** are SF Symbols, so those are data — but the
  *layout* of the brochure is not. A new section type means Swift.
- **Practice content** (journal prompts, exercises, recipes, massages) is still
  hardcoded in `Models.swift`. `practice_sessions` is a real table, but the
  written libraries are not yet.
