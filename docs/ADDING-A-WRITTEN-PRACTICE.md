# Adding a written practice

Journal prompts, movement sequences and recipes are rows in three tables
(migration `0021_written_practices.sql`). Adding, editing or retiring one needs
**no app release**. Everything below is done in the Supabase dashboard
(Table Editor, or the SQL editor).

| Practice tab section | Table | What a row needs |
|---|---|---|
| Journal Prompts | `journal_prompts` | `title` (the question), `prompt` (the framing under it), `theme` (the eyebrow) |
| Movement | `exercises` | `title`, `focus` ("Mobility", "Yoga"…), `duration_seconds`, `blurb`, `steps` |
| Food Recipes | `recipes` | `title`, `angle` ("Gut-friendly"…), `minutes`, `servings`, `blurb`, `ingredients`, `steps` |

All three also take `image_url`, `published` (default `true`), `sort_order`
and `instructor_id` (the guide, optional).
Leave `id` empty. The database assigns it.

## 1. Add the row

```sql
insert into public.recipes (title, angle, minutes, servings, image_url, blurb, ingredients, steps)
values ('Ginger Miso Broth', 'Warming', 20, 2, 'retreat-images/kyoto-2026-05.jpg',
        'A clear, restoring broth for a tired evening.',
        array['1 litre vegetable stock', '2 tbsp white miso', 'Thumb of ginger, sliced'],
        array['Simmer the stock with the ginger for 10 minutes.', 'Whisk in the miso off the heat.']);
```

A movement sequence's `steps` is a JSON list, in order. `name` is required and
`detail` is optional:

```json
[{"name": "Cat–Cow", "detail": "8 slow reps"}, {"name": "Savasana"}]
```

The table refuses anything else (`exercises_steps_shape`): an empty list, a step
without a name, or a detail that isn't text. Recipes refuse an empty
ingredient or method list.

**Photos.** `image_url` is `bucket/path.jpg` in Storage, the same as a
retreat's. Upload to `retreat-images` (see `ADDING-A-RETREAT.md`) or leave it
empty for a quiet gradient.

**Order.** Rows with a `sort_order` come first, lowest first. Rows without one
follow, oldest first.

**Drafts.** Insert with `published = false`, finish it over as many sittings as
you like, then flip it to `true`.

## 2. When it appears

The app reads these tables at most every five minutes, so a new row shows on
the next visit to that section after that. The app keeps the last library it
read on the phone, so a member who opened a section once can still open it
with no connection.

## 3. Editing, and taking one down

- **Edit freely.** A member's history keeps the title as it was when they
  practised it.
- **Never change or reuse an `id`.** The practice ledger, digital-retreat
  curricula and a member's saved journal reflections all point at it by id.
- **Take a practice down with `published = false`, not a delete.** It leaves the
  lists. A digital-retreat day that included it shrinks to what remains. Its
  history stays intact.

## 4. Optional: put it in a digital retreat, or name its guide

A digital retreat's `curriculum` points at the practice by kind and id:

```json
{"kind": "recipe", "content_id": 4, "note": "Make enough for tomorrow."}
```

To show a "Your guide" card on its page and list it in the guide's library,
set `instructor_id` to the guide's id (see `ADDING-AN-INSTRUCTOR.md`). A guide
who doesn't exist is refused:

```sql
update public.recipes set instructor_id = 'noa-castell' where id = 4;
```

## 5. Check it

```bash
curl -s "https://<host>/rest/v1/recipes?select=id,title&order=sort_order.asc.nullslast,id.asc" \
  -H "apikey: <anon key>" -H "Authorization: Bearer <anon key>"
```

A `200` lists what members see, which is published rows only.
