-- 0014_seed_program_finding_ground.sql
-- The first digital program: "Finding Ground", 7 days.
--
-- CONTENT, not schema. Kept as a migration because this project applies
-- everything by hand and a record of what was inserted is worth more than
-- tidiness. Safe to re-run: it upserts on the slug.
--
-- Every activity here points at the WRITTEN libraries (journal prompts,
-- movement sequences, recipes), which are hardcoded in Models.swift and so are
-- present on every build. None points at `practice_sessions`, because that
-- table is empty and an activity that cannot be opened cannot be completed —
-- which, under the unlock rule, would stall the program permanently.
--
-- APPLIED 2026-09-17 and verified: `days` = 7 and the curriculum authors 7,
-- which is the check at the bottom of this file — they can drift apart and the
-- catalog card would then disagree with the detail screen. 14 activities across
-- the 7 days. The document round-tripped through `ProgramCurriculum` and
-- rendered on device, which is the only way to catch a decode failure: it
-- FAILS SOFT, so a broken curriculum looks exactly like an unauthored one.
--
-- To add a guided audio/video day later: upload the media, insert the
-- practice_sessions row (set `program_only` true if it should not appear on the
-- Practice tab), then add {"kind":"session","content_id":<id>} to a day here.
-- No app release is involved.

insert into public.programs
    (id, title, lead, date_range, days, image_url, blurb, published, sort_order, curriculum)
values (
    'finding-ground',
    'Finding Ground',
    'Alma Guerra',
    null,                                   -- self-paced: the meta line comes from `days`
    7,
    'retreat-images/dolomites-2027-09.jpg',
    'Seven days of returning to the body — breath, movement, reflection and food, one day at a time.',
    true,
    10,
    $json$
{
  "overview": "A week of small, repeatable returns. Each day asks for twenty minutes and gives back a little more room than you had — beginning with arrival, moving through release and strength, and ending with something you are ready to start. Take the days at whatever speed your life allows; the next one waits for you.",
  "days": [
    {
      "day": 1,
      "title": "Arriving",
      "intention": "Land before you ask anything of the body.",
      "image_url": "retreat-images/dolomites-2027-09.jpg",
      "activities": [
        { "kind": "journal",  "content_id": 1, "note": "Answer from sensation, not from thought." },
        { "kind": "exercise", "content_id": 1 }
      ]
    },
    {
      "day": 2,
      "title": "Steadiness",
      "intention": "Find the floor. Everything else is built on it.",
      "image_url": "retreat-images/sedona-2026-06.jpg",
      "activities": [
        { "kind": "exercise", "content_id": 4, "note": "Slow is the whole instruction." },
        { "kind": "recipe",   "content_id": 1 }
      ]
    },
    {
      "day": 3,
      "title": "Letting go",
      "intention": "Set down one thing you have been carrying out of habit.",
      "image_url": "retreat-images/kyoto-2026-05.jpg",
      "activities": [
        { "kind": "journal",  "content_id": 2 },
        { "kind": "exercise", "content_id": 3, "note": "Undo the shape the week put you in." }
      ]
    },
    {
      "day": 4,
      "title": "Strength",
      "intention": "Steadiness you can stand on when it is asked for.",
      "image_url": "retreat-images/mallorca-2027-07.jpg",
      "activities": [
        { "kind": "exercise", "content_id": 2 },
        { "kind": "recipe",   "content_id": 3, "note": "Eat it warm, and slowly." }
      ]
    },
    {
      "day": 5,
      "title": "Kindness",
      "intention": "Speak to yourself the way someone who loves you would.",
      "image_url": "retreat-images/bali-2026-07.jpg",
      "activities": [
        { "kind": "journal",  "content_id": 4 },
        { "kind": "exercise", "content_id": 5, "note": "Long holds. Let the floor take the weight." }
      ]
    },
    {
      "day": 6,
      "title": "Nourishment",
      "intention": "Notice what already sustains you.",
      "image_url": "retreat-images/kyoto-2026-05.jpg",
      "activities": [
        { "kind": "recipe",  "content_id": 2, "note": "Make it tonight, for tomorrow." },
        { "kind": "journal", "content_id": 3 }
      ]
    },
    {
      "day": 7,
      "title": "Beginning",
      "intention": "Not the whole journey. The first honest step.",
      "image_url": "retreat-images/mallorca-2027-07.jpg",
      "activities": [
        { "kind": "journal",  "content_id": 5 },
        { "kind": "exercise", "content_id": 4, "note": "The same sequence as day two. Notice what changed." }
      ]
    }
  ],
  "closing": {
    "title": "You have come back seven times",
    "body": "That is the practice — not the week, but the returning. Everything you did here lives in the Practice tab, and it is yours whenever you want it. Begin again whenever the ground moves."
  }
}
    $json$::jsonb
)
on conflict (id) do update set
    title      = excluded.title,
    lead       = excluded.lead,
    date_range = excluded.date_range,
    days       = excluded.days,
    image_url  = excluded.image_url,
    blurb      = excluded.blurb,
    published  = excluded.published,
    sort_order = excluded.sort_order,
    curriculum = excluded.curriculum;

-- ---------------------------------------------------------------------------
-- Verification:
--   select id, title, days, published,
--          jsonb_array_length(curriculum -> 'days') as authored_days
--     from public.programs where id = 'finding-ground';
--   -- authored_days must equal `days`, or the detail screen and the catalog
--   -- card will disagree about how long the program is.
-- ---------------------------------------------------------------------------
