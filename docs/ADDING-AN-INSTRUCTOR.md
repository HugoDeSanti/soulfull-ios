# Adding an instructor

**No app release required.** A guide is a row in `instructors`, a portrait in
Storage, and their content pointed at them. All three are done in the Supabase
dashboard. Needs migration `0019_instructors.sql` applied first.

Until a guide has a row, nothing changes in the app: the Practice tab has no
Guides shelf, and a digital retreat's "with Alma Guerra" stays plain text.

---

## 1. Upload the portrait

Dashboard → **Storage** → `instructor-photos` → Upload.

- **Bucket:** `instructor-photos` (public, 2MB cap, JPEG/PNG).
- **Naming: `<instructor id>.jpg`**, e.g. `alma-guerra.jpg`. To replace a
  portrait, upload under a **new** name (`alma-guerra-2027.jpg`) and update the
  row. Phones cache images by path, so an overwrite under the same name can
  keep the old face on screen for a while.
- **Framing:** it is shown in a circle, 62pt on the shelf and 112pt on the
  profile. Centre the face in a square, ~800px. The same photo, heavily blurred,
  is the profile's background, so its colours set the page's mood.
- With no photo, the app shows the guide's initial on a tone picked from their
  id. That works fine; it isn't an error state.

## 2. Insert the row

```sql
insert into public.instructors (id, name, title, bio, photo_url, sort_order)
values (
  'alma-guerra',                              -- slug: lowercase, hyphens; never change it once content points at it
  'Alma Guerra',                              -- shown in full, everywhere
  'Breathwork · Somatic therapy',             -- a few words; shown as the eyebrow over the name
  'Slow, trauma-aware breathwork …',          -- a paragraph or two; blank lines are kept. Folds past ~260 characters
  'instructor-photos/alma-guerra.jpg',        -- bucket/path, or null
  1                                           -- shelf order; null sorts last, then by name
);
```

`published` defaults to `true`. Set it to `false` to take a profile down. The
guide's sessions and digital retreats stay in the library, their credits
become plain text again, and anyone who opens the profile from an old screen
is told it isn't available.

## 3. Point their content at them

```sql
update public.practice_sessions set instructor_id = 'alma-guerra' where lead = 'Alma Guerra';
update public.programs          set instructor_id = 'alma-guerra' where id = 'finding-ground';
```

A trigger then keeps each row's `lead` equal to the guide's `name`. Rename the
guide once in `instructors` and every credit follows. Hand-editing `lead` on a
linked row is reverted. `practice_plays.creator` is not touched: it is the
payout snapshot, taken at play time, and history does not move.

The profile's library is their **published** digital retreats plus their
sessions that appear on the Practice tab. `program_only` media belongs to its
program and is reached from there. Journal prompts, movement and recipes are
house content with no guide.

## 4. Optional: link their own account

If the guide has a member account (they signed up in the app), link it:

```sql
update public.instructors
   set user_id = (select id from auth.users where email = 'alma@example.com')
 where id = 'alma-guerra';
```

This does two things. Their **Following** count becomes the number of guides
their account follows (members follow guides, so that is what a guide can
follow; unlinked, it reads 0). And on their own page the Follow button becomes
"This is your profile". `user_id` never reaches any client: column grants keep
it server-side, so a profile can't be used to find a guide's personal account.

---

## What members see of each other here

"Followed by Theo R., Nia K. and 210 others" shows up to three faces: friends
first, then members with a photo, then the most recent. It only shows members
who have **Share my practice** on (the same switch as the Community feed). A
member who has turned it off is counted but never shown. The viewer is never
one of the faces; the app adds "you" itself. Nobody can list a guide's
followers. `instructor_social()` answers the count and at most three
abbreviated names.

## Verify

After inserting, pull to refresh isn't needed: the catalog cache is 5 minutes.
Relaunch the app and check the Guides shelf on the Practice tab, the profile,
and the "with …" chip on the guide's digital retreat. The SQL checks for
permissions (a guest can't follow, `user_id` is unreadable) are at the bottom
of `0019_instructors.sql`.
