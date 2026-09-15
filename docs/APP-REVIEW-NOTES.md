# App Review notes — Soulfull Gatherings 1.0

Paste the **Review notes** block below into App Store Connect → your build →
*App Review Information*. Everything above it is context for you, not Apple.

> **Rewritten 2026-09-03.** Sign-in briefly became mandatory that day and was
> then softened the same day; the notes were rewritten twice. Do not restore
> either earlier version from git history — the first claimed no account exists
> at all, the second claimed the app can't be opened without one.

---

## How account gating works now

Browsing is open to an anonymous guest: the retreat catalog, retreat detail, the
Practice landing and every list screen. An account is asked for only when the
user opens an actual practice — a session player, a journal prompt, an exercise,
or a recipe. The sheet appears at that moment and, on success, the app
continues into whatever they tapped.

Three consequences for review:

1. **A demo account is still needed** — not to open the app, but to see any
   practice content. A reviewer without one can browse the whole catalog and
   read every list, and will be stopped at the first thing they try to open.
2. **Guideline 4.8 is satisfied outright.** Sign in with Apple is the only
   third-party login offered — Google was built and then removed before
   shipping — so there is no equivalent-option obligation to meet.
3. **Guideline 5.1.1(i) was designed around, not argued around.** See below.

### Guideline 5.1.1(i) — why this shape

> "Apps may not require users to enter personal information to function, except
> when directly relevant to the core functionality of the app or required by law."

The first cut of this feature put a registration wall at the end of onboarding,
which blocks a browsable catalog behind a login — the classic trigger for this
rule. That was replaced with just-in-time gating on the same day. Nothing the
app *shows* now requires an account; only the things it *saves against you* do —
practice history and written reflections — which is squarely "directly relevant
to core functionality."

If a reviewer still queries it, the honest answer is in the notes block below.

## What v1 still does *not* need

- **Nothing is purchasable.** `AppFeatures.paymentsEnabled` is `false`, so the
  Stripe rail is unreachable — no seeded booking, no IAP justification.
- **Account deletion** is in-app under the You tab (Guideline 5.1.1(v)).
  Signing out drops the user back to a guest session and leaves them where they
  were — the app stays fully browsable.

  Deletion also **revokes the Sign in with Apple grant** via Apple's
  `/auth/revoke`, which 5.1.1(v) requires of any app offering both. Deleting the
  Supabase user is not enough on its own: without the revoke the app stays
  listed under *Settings → Apple ID → Sign in with Apple*, and that is the thing
  a reviewer actually looks at. The setup this needs is in the checklist below —
  **it is not automatic, and the app ships non-compliant until it is done.**

## Accounts and identifiers

| | |
|---|---|
| **Apple Developer account** | `app@soulfullgatherings.com` |
| **Bundle ID** | `com.soulfullgatherings.app` |
| **Team ID** | `W346837424` (set as `DEVELOPMENT_TEAM` in gitignored `Config/Secrets.xcconfig`) |
| **Sign in with Apple** | Entitlement generated from `project.yml`; `APPLE_ID_AUTH` capability **verified enabled** on the App ID (2026-09-03) |

> `app@soulfullgatherings.com` is the **developer account**, not the customer
> support address. `LegalLinks.supportEmail` is now `info@soulfullgatherings.com`
> — the same inbox the three published legal pages give for privacy requests,
> support and bookings. It is the Support link in the You tab and the
> destination of every "Request a place" enquiry, so it has to stay monitored.

## Before you submit — check each of these

**Sign in with Apple revocation — Guideline 5.1.1(v), and a rejection if skipped:**

- [x] **Migration `0010_apple_credentials.sql` is applied** to the live
      project (2026-09-10). Verified: RLS on, 0 policies, 0 grants to
      `anon`/`authenticated`, FK `on delete cascade`, and both client roles get
      `42501 permission denied` rather than a row.
- [x] **A Sign in with Apple key (`.p8`) exists** for `com.soulfullgatherings.app`
      — Key ID `5224W8727Y`, created 2026-09-10 — and the four secrets are set:
      `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `APPLE_CLIENT_ID`
      (the **bundle ID**, not a Services ID). Verified by minting a client
      secret and calling Apple's `/auth/revoke`, which answered 200 — so the
      key, team and bundle ID all authenticate. The `.p8` lives untracked at the
      repo root and is gitignored; **it must never be committed.**
- [x] **`store-apple-token` is deployed** and `delete-account` **re-deployed**
      (2026-09-10). Smoke-tested: both reject unauthenticated callers with 401,
      and `store-apple-token` boots and sees its secrets (a guest JWT gets the
      expected 403, not a 501).
- [ ] **Verified end to end on a real device**: sign in with Apple → You tab →
      Delete account → *Settings → your name → Sign-In & Security → Sign in with
      Apple* no longer lists Soulfull. A simulator cannot prove this.

**Auth — the app is unusable if any of these is wrong:**

- [ ] **Supabase → Authentication → Providers → Apple = ON**, with
      `com.soulfullgatherings.app` in *Client IDs* and *Secret Key* left blank.
      The native token flow checks the token's `aud` against that list; empty
      rejects every Apple sign-in. This is the only provider to configure.
- [ ] **Supabase → Authentication → URL Configuration → Redirect URLs** contains
      `soulfull://auth-callback` — this is what makes email-confirmation links
      reopen the app.
- [ ] **Anonymous sign-ins stay ON.** The pre-sign-in stages still use a guest
      session for catalog reads.
- [ ] **The demo account below exists and is email-confirmed**, and you have
      used it on a clean install to open one practice end to end.
      "Confirm email" is currently ON for this project, so an unconfirmed
      account can never complete sign-in.

**Content and legal:**

- [ ] **Age rating answers match the content.** The app has no alcohol, tobacco
      or drug references, so *Alcohol, Tobacco, or Drug Use or References* is
      **None** and the app rates 4+. That is only true as long as nobody adds a
      brochure line like the "A winery experience" that was removed on
      2026-09-11 — a wrong rating is a Guideline 2.3.6 rejection.

- [ ] `LegalLinks.privacyPolicy` and `LegalLinks.terms` point at **live, public**
      pages, and the same privacy URL is entered in App Store Connect.
      A privacy policy URL that 404s is an automatic rejection.
- [ ] `LegalLinks.supportEmail` is a monitored inbox.
- [ ] The `retreats` table contains retreats that have **not yet started**.
      The app filters on `start_date > today` (a retreat under way can no longer
      be joined, so offering a place on it is a wrong price and a wrong date),
      and `Retreat.hasBegun` applies the same rule to the offline fallback. A
      stale catalog therefore shows as empty rather than wrong — but an empty
      catalog reads as a broken app, so keep at least a few ahead.
      As of 2026-09-11: Lapland, Chamonix, Mallorca, Dolomites (all 2027).
- [ ] If you seeded `practice_sessions`, open each track once on a device and
      confirm the media actually plays from the `practice-media` bucket.
- [x] `0008_practice_progress.sql` is applied (2026-09-06). Practice history,
      the Continue card and the creator-payout ledger are live.
- [ ] Privacy nutrition labels in App Store Connect match
      `SoulfullGatherings/PrivacyInfo.xcprivacy` — including **Product
      Interaction**, added when practice history started being recorded.
- [ ] If you seeded `programs` (`0006_programs.sql`), the Digital Retreats shelf
      appears on Home. Until then it is hidden by design — not a bug.

## Creating the demo account

Sign-ups need email confirmation, so the account must be created pre-confirmed
rather than through the app. In the Supabase dashboard: **Authentication →
Users → Add user → Create new user**, tick **Auto Confirm User**, then fill the
credentials you put in the review notes below.

Sign in with it once on a clean install before submitting. The reviewer answers
the four onboarding questions first, then reaches the gate — so the credentials
must work from a fresh launch, not just a warm one.

---

## Review notes — paste this into App Store Connect

```
Soulfull Gatherings is a wellness retreat and practice app.

NO ACCOUNT NEEDED TO BROWSE
The app opens straight into the retreat catalog and the practice library. You
can read everything — retreats, dates, pricing, and every practice listing —
as a guest, with no sign-in at all.

DEMO ACCOUNT (needed only to open a practice)
  Email:    <fill in>
  Password: <fill in>
Opening a guided session, journal prompt, movement sequence or recipe saves it
to your practice history, so those ask you to sign in first. Use the account
above via "or / Email", or Sign in with Apple. After signing in the app
continues straight into whatever you tapped.

WHY THOSE SCREENS ASK FOR AN ACCOUNT
Opening a practice records it to that member's practice history on our server —
which session, how much of it, and when — so the app can offer to resume it and
so we can pay the guide who recorded it. There is nowhere to put that for an
anonymous user. Written journal reflections are per-member too, but they are
held only on the device and are never uploaded. Nothing that is merely
browsable is behind the prompt. Account creation collects only a name and an
email address, and is covered by our privacy policy.

SIGN IN WITH APPLE
Offered and listed first. It is the only third-party login in the app; the
alternative is an email and password.

ACCOUNT DELETION
In-app under the "You" tab -> Delete account (Guideline 5.1.1(v)). For an
account created with Sign in with Apple, deletion also calls Apple's
/auth/revoke, so the app is removed from Settings -> Apple ID -> Sign in with
Apple at the same time.

NO PURCHASES IN THIS VERSION
This version contains no in-app purchases and no payment flow of any kind —
there is no payment SDK in the binary. Retreat pages show details and pricing
for information; the call to action opens an email enquiry to our team.
Bookings are handled offline by our staff.

NO AI
The app contains no AI features, no chatbot and no generative content. Every
piece of text in it was written by our team.

CONTENT NOTE
"Coming soon" on the Somatic Exercises, Breathwork and Meditation cards is intentional:
those guided audio/video tracks are being recorded and will be enabled from the
server. The Journal, Movement and Recipes sections are complete and
fully browsable.

CONTACT
<support email> — happy to walk through anything.
```

## Stripe justification — only if reservations are enabled

Flipping `AppFeatures.paymentsEnabled` to `true` re-adds three obligations:
a demo account with a **paid booking already seeded** (a reviewer cannot complete
a live charge), the paragraph below, and curated post-purchase content for every
reservable retreat — today only Mallorca has it, so any other retreat lands on
empty Packing and Guides screens.

```
PAYMENTS (Guideline 3.1.3(e) — goods and services outside the app)
Reservations are for physical, in-person retreats at named real-world locations
on fixed calendar dates — travel, accommodation, meals and in-person coaching
delivered entirely offline. Under Guideline 3.1.3(e) these are goods and
services consumed outside the app, so payment is processed by Stripe rather than
in-app purchase. Nothing digital is unlocked by the payment; the post-purchase
screens are trip logistics (checklists, packing, scheduling a 1:1 with a guide
on site) for a trip the member is physically attending.

To review the reserved-retreat experience without completing a charge, sign in
with the demo account above — it already has a confirmed reservation.
```
