# Digital Programs (the "Programs" tab)

Self-paced, multi-day guided journeys — breathwork, meditation, movement,
reflection and food — that a member enrols in for free and works through one
day at a time. Shipped as a fourth tab.

Decided 2026-09-17 with Hugo. This document is the spec; the code is the
authority once it exists.

---

## The rules

| Question | Answer |
|---|---|
| **Access** | Free. Enrolling requires an **account** (via `AccountGate`, exactly like opening a practice). Browsing the catalog and reading a program's overview stay open to a guest. |
| **Shape** | A program is an ordered list of **days**. Each day carries 2–4 **activities** drawn from the practice libraries. |
| **Unlock** | Day N+1 opens when **both** hold: every activity in Day N is complete, **and** the local calendar date has moved past the date Day N was completed on. Day 1 is open the moment you enrol. |
| **"Complete"** | Automatic. An activity is complete when the existing ledger says so — media played through, a journal prompt with something written against it, 45s dwell on a written piece. There is no "mark as done" button. |
| **Content** | Mostly the shared practice libraries; a program may also carry **program-only** sessions that never appear on the Practice tab (`practice_sessions.program_only`). |
| **Yoga** | Lives in the existing **Movement** library as step sequences. No new `PracticeCategory`. |
| **Tab** | "Programs", fourth in `BottomNav`. Digital only — in-person retreats stay on Home. Home's existing "Digital Retreats" shelf becomes the entry point. |
| **Layout** | In-progress program leads the screen; catalog beneath. Multiple enrolments allowed. |
| **Nudges** | A local notification the morning a day opens, **plus** an in-app surface on Home. |

### Two rules that are easy to get wrong

1. **An activity only counts toward a day if it was completed *after* that day
   unlocked.** `practice_progress.completed` is latched for all time, so
   without this a member with any history at all would have days 1–4 marked
   done the instant they enrolled, and the pacing — the entire point — would
   evaporate. The comparison is `last_played_at >= dayUnlockedAt(n)`.
   A consequence worth knowing: the same prompt can appear on day 2 and day 6
   and must be *re-done* the second time. That is deliberate.

2. **Day completion is latched, activity completion is not.** Once a day's
   completion row is written it stays written, even if the curriculum later
   gains an activity that day never had. Seeding media into an existing
   program must not retroactively un-finish someone's week.

### Why the day/progress state is NOT in `practice_plays`

`practice_plays` is the creator-payout ledger. It is append-mostly, has no
delete policy, and migration 0012 just narrowed its `content_kind` vocabulary.
A program day is neither content nor a payable event — it is membership state,
and a member leaving a program should be able to take it with them. So
enrolment and day completion get their own two small tables, and **the
activities inside a day record to `practice_plays` exactly as they do from the
Practice tab.** A creator is paid the same whether their session was found in
the library or inside a program, and nothing about payouts changes.

---

## Schema (migration 0013)

`programs` gains:

| Column | Why |
|---|---|
| `blurb text` | Catalog subtitle. |
| `curriculum jsonb` | The days and their activities. Same pattern as `retreats.experience`: hand-authored, snake_case, **fails soft** — a malformed document logs and yields a program with no days rather than taking down the tab. |
| `published boolean default false` | A draft program is invisible. `fetchPrograms()` filters on it. |
| `sort_order integer` | Catalog order; `nulls last, title`. |
| `date_range` | **Now nullable.** A self-paced program has no calendar window; the meta line is derived from `days`. |

`practice_sessions` gains `program_only boolean default false` — excluded from
`fetchPracticeSessions(category:)` so it never shows on the Practice tab, still
fetchable by id for a curriculum.

New, both RLS owner-scoped and both denied to anonymous guests (belt and
braces — the client already gates on `hasAccount`):

```
program_enrollments      (user_id, program_id) pk, enrolled_at, completed_at
program_day_completions  (user_id, program_id, day_number) pk, completed_at
```

### Curriculum shape

```jsonc
{
  "overview": "One paragraph on the arc of the week.",
  "days": [
    {
      "day": 1,
      "title": "Arriving",
      "intention": "Land before you ask anything of the body.",
      "image_url": "retreat-images/mallorca-2027-07.jpg",
      "activities": [
        { "kind": "journal",  "content_id": 1, "note": "Longhand if you can." },
        { "kind": "exercise", "content_id": 1 },
        { "kind": "session",  "content_id": 12 }
      ]
    }
  ],
  "closing": { "title": "…", "body": "…" }
}
```

`kind` is a `PracticeContentKind` — `session` / `journal` / `exercise` /
`recipe`. **An activity whose content cannot be resolved is dropped from the
day** (logged, not fatal): a `session` id that isn't in `practice_sessions`
yet would otherwise be impossible to complete and would stall the program
forever. This is what lets a curriculum reference media before it is uploaded.

---

## Open / deferred

- **`practice_sessions` is empty**, so the seeded program uses the written
  libraries only. Adding media activities is an edit to the jsonb — no release.
- **Un-enrolling** clears the enrolment and its day rows; practice history
  (and therefore creator payouts) survives untouched.
- **Notification time** is 08:00 local on the unlock date, not midnight. The
  day *opens* at midnight per the rule; waking someone to tell them is a
  different decision.
- The device clock decides "what day is it". Winding it forward skips the
  wait. Accepted: this is a free wellness program, not an exam.
