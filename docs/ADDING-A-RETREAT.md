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
- **Naming: `<place>-<yyyy>-<mm>.jpg`** — `mallorca-2027-07.jpg`, `lapland-2027-01.jpg`.
  Place first so listing the bucket groups every Mallorca together, which is how
  you actually browse it. Year-month because retreats recur annually in the same
  place, so the place alone collides; the day would be noise. **Not the row id** —
  ids mean nothing to a human scanning a bucket, and if a row is ever recreated
  the file would be misnamed while the photo is unchanged. Lowercase and hyphens,
  so the URL needs no escaping.
- **Size:** it is used full-bleed behind type on the detail hero and the
  retreats stack. ~2000px on the long edge is plenty; bigger only costs the
  user bandwidth.
- **Replacing a photo:** upload over the same name with `x-upsert: true`. Clients
  revalidate against the ETag, so a replacement is picked up on the next launch.
  For an instant change, upload under a new name and update the row — which the
  naming convention supports, since a new shoot is usually a new date anyway.
- **Tone:** the app lays cream type over the top of it. A photo that is bright
  and busy in its upper third will fight the header — `PhotoBackdrop` darkens
  the top band, but it can't rescue a white sky.

> **The photos already there** were uploaded on 2026-09-14 from the app bundle,
> and all seven rows point at them. The `retreat-*` imagesets stay in
> `Assets.xcassets` — the Practice mock content still borrows them as placeholder
> art — but nothing in the retreat catalog reads them any more.
>
> Note the originals are small: five of the seven are only 736px wide, which the
> full-bleed hero upscales on a 3× phone. If you are reshooting, ~2000px on the
> long edge is the target.

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
  'retreat-images/patagonia-2028-03.jpg',   -- bucket/path, NOT an asset name
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

### Trip photography

If you supply `post_booking`, give it its screen photography too — otherwise
those screens render the espresso ground alone:

```json
"post_booking": {
  "welcome_image":       "retreat-images/mallorca-2027-07/welcome.jpg",
  "featured_todo_image": "retreat-images/mallorca-2027-07/featured-todo.jpg",
  "todos_image":         "retreat-images/mallorca-2027-07/todos.jpg",
  "packing_image":       "retreat-images/mallorca-2027-07/packing.jpg",
  "guides_image":        "retreat-images/mallorca-2027-07/guides.jpg"
}
```

Convention: a **folder per retreat instance**, named after the hero file's stem
— `retreat-images/mallorca-2027-07/…`. Everything for one trip sits together,
and `ImageSource` splits on the first slash only, so the bucket is still
`retreat-images` and the rest is the object path.

These were hardcoded `Image("mb-villa")` in the views until 2026-09-14 — "mb"
for *Mallorca brochure*. That was fine while Mallorca was the only trip with
content and wrong the moment it wasn't: reserving Patagonia would have shown a
Mallorca villa on the packing screen, confidently, with nothing to suggest
anything was off. Leaving them out now renders a deliberate blank instead.

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

## Other imagery already in the bucket

Uploaded 2026-09-14 when the post-purchase screens stopped hardcoding them:

| Path | Used by |
|---|---|
| `mallorca-2027-07/{welcome,featured-todo,todos,packing,guides}.jpg` | the four trip screens, via `post_booking` |
| `mallorca-2027-07/{hero,checkout,cycle,dinner,recover,swim,yoga}.jpg` | **nothing yet** — they were in the app bundle unreferenced. Parked here so a future brochure can point at them (element photography, say) without a release. |
| `members/g-martinez.jpg` | **nothing** — the testimonial renders quote, author and attribution, never a photograph. See below. |

> **The member photograph has never been displayed.** `member-gmartinez` sat in
> the asset catalog at 1.1MB, referenced by no view and no mirror card — the
> testimonial section renders text only. It is now in Storage and out of the
> bundle, but showing it would need a design decision and an avatar in
> `testimonialSection`, which nobody has asked for. If you do want it, the field
> to add is `testimonial.image`.

## What still needs a release

- The **four element icons** are SF Symbols, so those are data — but the
  *layout* of the brochure is not. A new section type means Swift.
- **Practice content** (journal prompts, movement sequences, recipes) is still
  hardcoded in `Models.swift`. `practice_sessions` is a real table, but the
  written libraries are not yet.
