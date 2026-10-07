# Creator payouts: setting a month's pool and paying guides

Guides earn on **time heard** and are paid a **share of a monthly pool**
(decided 2026-10-07). Each guide sees their own figures on the guide dashboard
on their You tab. The team runs everything below in the Supabase SQL editor.
Schema and reasoning: `supabase/migrations/0026_guide_dashboard.sql`.

## The rule

- Each month's **pool** is **15% of the app's revenue after costs** (the
  Soulfull and Nadia Labs agreement, 2026-10-07). The team works it out and
  enters it.
- A guide's **share** is the seconds of their sessions heard that month, over
  the seconds heard across every guide's sessions that month.
- A guide's **earnings** for the month are the pool times their share,
  rounded down to the cent, so the shares never add up to more than the pool.

What counts:

- **Sessions only** (audio and video). Journal prompts, movement and recipes
  show on the dashboard (who they reached) but take no part in the pool.
- **Time actually heard**, as `PlaybackReporter` measures it: seeking and
  pausing add nothing. The ledger caps each play at the session's length.
- **Not a guide's own listening.** Plays by the account linked to a guide never
  count toward that guide.
- **Plays by members who later deleted their account still count.** The row
  is anonymised, not deleted, because the guide earned it.
- A play belongs to the guide its session named **when it was played**
  (`practice_plays.instructor_id`, stamped by the server). Reassigning a
  session later doesn't move past earnings.
- **Months are UTC months.**
- A session with no guide (`instructor_id` null, like the "Soulfull Studio"
  placeholders) is in nobody's share and doesn't dilute anyone's.

## Each month

### 1. Set the pool

The pool is 15% of the month's revenue after costs, so it is final only once
the month's revenue and costs are known. It can go in earlier as a running
figure and be corrected later. Before the month ends, guides see an estimate
from their share so far. Until a pool is set, they see their share and no
amount. Say how the figure was reached in `note`.

```sql
insert into public.creator_pools (month, amount_cents, currency, note)
values (date '2026-10-01', 300000, 'usd', 'October: 15% of $20,000.00 revenue after costs')
on conflict (month) do update
   set amount_cents = excluded.amount_cents,
       currency     = excluded.currency,
       note         = excluded.note;
```

`month` is always the **first day** of the month (the table refuses any other
day). `amount_cents` is in the currency's minor unit: $3,000.00 is `300000`.

### 2. After the month closes, run the payout

```sql
select name, instructor_id,
       round(seconds_heard / 60.0)         as minutes_heard,
       round(100.0 * seconds_heard / nullif(pool_seconds, 0), 2) as share_pct,
       earned_cents, currency
  from public.creator_pool_shares
 where month = date '2026-10-01'
 order by earned_cents desc nulls last;
```

This is the same view the dashboard reads, so what you pay is what each guide
already sees. Before paying, sanity-check the ledger for implausible rows (see
`supabase/functions/README.md`, "practice_plays is client-written").

### 3. Mark it paid

```sql
update public.creator_pools set paid_at = now() where month = date '2026-10-01';
```

Each guide's dashboard then shows the month as **Paid** with the date, and it
counts toward their **Paid to date**.

## Who sees a dashboard

Only a guide whose member account is linked (`instructors.user_id`, see
`docs/ADDING-AN-INSTRUCTOR.md` §4). An unlinked guide still earns: their
minutes are in the shares. They just can't see them in the app.

## What the dashboard never shows

No member is named, pictured or counted on their own. "People" is a distinct
count of accounts, so the dashboard can't be used to find out who listened.

## Before going live

- Remove or replace the placeholder guides and sessions first (CLAUDE.md →
  Current state). Their test plays stay in the ledger. Leave any month that
  holds them out of a real payout, or set its pool only after the
  placeholders are gone.
- Client-reported seconds are **capped, not proven**. For automatic payouts at
  scale, move ledger writes behind an Edge Function that cross-checks Storage
  access logs (`supabase/functions/README.md`).
- The pool is agreed at 15% of revenue after costs. Costs will include the
  fees Apple takes and cloud hosting. The rest of the list is still an open
  point in the agreement. The app holds only the
  amount the team enters, never the percentage.
