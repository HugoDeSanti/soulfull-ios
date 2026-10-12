# Adding an instructor

**No app release required.** A guide is a row in `instructors`, a portrait in
Storage, and their content pointed at them. All three are done in the Supabase
dashboard. Migrations `0019_instructors.sql` (2026-09-28) and
`0022_written_practice_guides.sql` (2026-09-29) are applied.

A guide appears on the pages of what they made: a "Your guide" card on each
digital retreat, movement sequence, recipe and journal prompt that names them,
and a face chip in the player for their sessions. They never appear on the
Practice landing. Content with no guide shows no card.

> ⚠️ **The five guides live today are placeholders**: Alma Guerra, Inés Aranda,
> Tomás Ferrer, Noa Castell and Julián Ros. The people are invented, the bios
> were written for them, and the faces are AI-generated. They were seeded on
> 2026-09-28 so the feature has something to show. **Remove them, or replace
> them with real guides, before any build goes to App Review.** See *Removing
> the placeholder guides* at the end.

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
guide once in `instructors` and every credit follows. A name is at most 64
characters (0030); a longer one is refused with 23514. Hand-editing `lead` on a
linked row is reverted. `practice_plays.creator` is not touched: it is the
payout snapshot, taken at play time, and history does not move.

The profile's library is their **published** digital retreats, their sessions
that appear on the Practice tab (`program_only` media belongs to its program and
is reached from there), and the written practices that name them below.

### Written practices: journal prompts, movement, recipes

Each one names its guide on its own row, the same `instructor_id` column
sessions and digital retreats have (migration 0022). A guide who doesn't exist
is refused:

```sql
update public.exercises       set instructor_id = 'alma-guerra' where id = 4;
update public.journal_prompts set instructor_id = 'alma-guerra' where id = 1;
```

It is **display only**. It puts the guide on the page and in their library,
and it does not pay them: the written libraries record no creator in the
payout ledger. (Until 0022 this was a separate `practice_credits` table, from
when these libraries were Swift code with no row to hold the column.)

## 4. Optional: link their own account

If the guide has a member account (they signed up in the app), link it:

```sql
update public.instructors
   set user_id = (select id from auth.users where email = 'alma@example.com')
 where id = 'alma-guerra';
```

**Linking replaces the guide's name with the account's** (0027). From then on
the name lives on the member's profile (`profiles.first_name` / `last_name`,
which the server joins into `full_name`, 0033): renaming the
member renames the guide and the `lead` on their sessions and digital
retreats, and editing the guide's name in the dashboard is reverted. A guide's
name is public in full, where Community shows members as "First L.". An
account with no name yet leaves the guide's name until it gets one.

Linking also does three things. Their **Following** count becomes the number of guides
their account follows (members follow guides, so that is what a guide can
follow; unlinked, it reads 0). On their own page the Follow button becomes
"This is your profile". And their You tab gains the **guide dashboard** (0026):
who practiced with them, what each month's pool paid them, and this month so
far. Without the link a guide has no dashboard at all; their minutes still
count toward their share. `user_id` never reaches any client: column grants
keep it server-side, so a profile can't be used to find a guide's personal
account. How payouts are worked out: `docs/CREATOR-PAYOUTS.md`.

---

## What members see of each other here

"Followed by Theo R., Nia K. and 210 others" shows up to three faces: friends
first, then members with a photo, then the most recent. It only shows members
who have **Share my practice** on (the same switch as the Community feed). A
member who has turned it off is counted but never shown. The viewer is never
one of the faces; the app adds "you" itself. Nobody can list a guide's
followers. `instructor_social()` answers the count and at most three
abbreviated names.

## Removing the placeholder guides

```sql
-- Content pointing at them loses its guide card (on delete set null); sessions
-- and digital retreats fall back to their plain `lead` text.
-- Follows go with them (cascade).
delete from public.instructors
 where id in ('alma-guerra', 'ines-aranda', 'tomas-ferrer', 'noa-castell', 'julian-ros');
```

Then delete the five `<id>.jpg` files from the `instructor-photos` bucket in the
dashboard. Deleting `storage.objects` rows in SQL does not delete the files.
To keep a slot and only swap in the real person, update the row (name, title,
bio) and upload a new photo under a new name. Finding Ground's credit then
follows the new name automatically.

## Verify

After inserting, pull to refresh isn't needed: the catalog cache is 5 minutes.
Relaunch the app and open something the guide made: its page should show the
"Your guide" card, and the card should open their profile. The SQL checks for
permissions (a guest can't follow, `user_id` is unreadable) are at the bottom
of `0019_instructors.sql`.
