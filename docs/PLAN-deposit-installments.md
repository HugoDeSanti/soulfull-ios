# Future Plan — Deposit + Installments Billing

**Status:** Parked (not implemented). Reserve currently charges the **full price as a single Stripe PaymentIntent**. This documents how we'd later split it.

## Goal

For curated retreats (e.g. Mallorca), charge a **deposit now** + the remaining balance as a small number of **scheduled monthly payments** — matching the brochure:

- Total €5,678 → **€800 deposit today**, then **2 × €2,439, billed monthly**.

Today the deposit/installment breakdown is **presentational copy only** (`RetreatExperience.PostBooking.Checkout`); the live charge is the full amount via the existing flow.

## Recommended mechanism

**Deposit PaymentIntent with `setup_future_usage: off_session` + server-scheduled off-session installments.**

- The deposit `PaymentIntent` charges €800 *and* vaults the card (saved payment method).
- A scheduled job creates off-session `PaymentIntent`s for each installment on its due date.

Chosen over Stripe **Subscriptions/Schedules** because this is a *fixed, finite* 3-payment arc, not an open-ended recurring plan. (Subscriptions remain an option if we'd rather Stripe own dunning/retries/SCA emails wholesale — revisit if the off-session SCA handling below proves heavy.)

## Work breakdown

### Database
- **New `booking_payments` table** — one row per scheduled payment (cleaner than columns on `bookings`; gives history + per-payment receipts):
  - `id`, `booking_id` (fk), `sequence` (0 = deposit, 1..n = installments), `amount`, `currency`, `due_at`, `status` (`scheduled`/`paid`/`failed`/`canceled`), `stripe_payment_intent_id`, `created_at`, `updated_at`.
  - RLS: owner-read only (mirror `bookings`); writes via service role (webhook / scheduled fn).
- **`bookings`** gains: `plan` (`full`|`installments`), `stripe_payment_method_id`, `next_payment_at`.

### Edge Functions
- **`create-payment-intent`** — accept a `plan` param. For `installments`: set `setup_future_usage: off_session` on the deposit intent, persist the saved PM on success, and write the future `booking_payments` rows.
- **`charge-installment`** (new) — invoked by **Supabase `pg_cron`** (or an external scheduler) when a `booking_payments` row is due; creates an off-session `PaymentIntent` on the saved PM.
- **`stripe-webhook`** — extend `payment_intent.succeeded` / `payment_failed` handling to mark the matching `booking_payments` row, advance `bookings.next_payment_at`, and flip booking status when the final payment clears.

### The hard part — off-session SCA & dunning
- An off-session installment can return `requires_action` (3-D Secure). Need to:
  - Detect it server-side, mark the payment `failed`/`action_required`.
  - Notify the member (push + email) to re-authenticate in-app.
  - Surface an in-app "complete your next payment" path that presents PaymentSheet for that intent.
- Retry/dunning policy for hard declines (retry cadence, grace period, cancellation rules).

### Client (iOS)
- `RetreatCheckoutView` gains a **plan picker** (pay in full / deposit + 2 installments).
- Deposit collected via PaymentSheet (with card save).
- A **Payments** section in the experience hub showing the schedule + each payment's status — this also makes the "Set your installment dates" to-do real (currently informational).

## Complexity

**Medium–High.** ~1 migration, 1 new + 2 modified Edge Functions, `pg_cron` config, webhook branches, and the SCA/dunning UX. Mostly backend + payments compliance (card vaulting, off-session auth). The iOS surface is comparatively small.

## Touch points in current code
- `supabase/functions/create-payment-intent/`, `supabase/functions/stripe-webhook/`
- `supabase/migrations/` (new migration), `bookings` table
- `SoulfullGatherings/Core/Services/PaymentService.swift`
- `SoulfullGatherings/Features/Retreats/RetreatDetailViewModel.swift`
- `SoulfullGatherings/Features/Retreats/PostPurchase/RetreatCheckoutView.swift` (plan picker)
- `RetreatExperience.PostBooking.Checkout` already models the deposit/installment copy.
