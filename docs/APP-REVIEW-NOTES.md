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
a recipe, a massage. The sheet appears at that moment and, on success, the app
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

## Accounts and identifiers

| | |
|---|---|
| **Apple Developer account** | `app@soulfullgatherings.com` |
| **Bundle ID** | `com.soulfullgatherings.app` |
| **Team ID** | `W346837424` (set as `DEVELOPMENT_TEAM` in gitignored `Config/Secrets.xcconfig`) |
| **Sign in with Apple** | Entitlement generated from `project.yml`; `APPLE_ID_AUTH` capability **verified enabled** on the App ID (2026-09-03) |

> `app@soulfullgatherings.com` is the **developer account**, not necessarily the
> customer support address. `LegalLinks.supportEmail` is currently the
> placeholder `hello@soulfullgatherings.com` and is what users see in the app —
> it is the Support link in the You tab and the destination of every "Request a
> place" enquiry. Point it at whichever inbox is actually monitored.

## Before you submit — check each of these

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

- [ ] `LegalLinks.privacyPolicy` and `LegalLinks.terms` point at **live, public**
      pages, and the same privacy URL is entered in App Store Connect.
      A privacy policy URL that 404s is an automatic rejection.
- [ ] `LegalLinks.supportEmail` is a monitored inbox.
- [ ] The `retreats` table contains only retreats that have **not yet ended**.
      The app filters on `end_date >= today`, so a stale catalog shows as empty
      rather than wrong — but an empty catalog reads as a broken app.
- [ ] If you seeded `practice_sessions`, open each track once on a device and
      confirm the media actually plays from the `practice-media` bucket.
- [ ] Privacy nutrition labels in App Store Connect match
      `SoulfullGatherings/PrivacyInfo.xcprivacy`.
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
Opening a guided session, journal prompt, exercise, recipe or massage saves it
to your practice history, so those ask you to sign in first. Use the account
above via "or / Email", or Sign in with Apple. After signing in the app
continues straight into whatever you tapped.

WHY THOSE SCREENS ASK FOR AN ACCOUNT
Practice history and written reflections are per-member data — they are stored
against the account and synced across devices, so there is nowhere to put them
for an anonymous user. Nothing that is merely browsable is behind the prompt.
Account creation collects only a name and an email address, and is covered by
our privacy policy.

SIGN IN WITH APPLE
Offered and listed first. It is the only third-party login in the app; the
alternative is an email and password.

ACCOUNT DELETION
In-app under the "You" tab -> Delete account (Guideline 5.1.1(v)).

NO PURCHASES IN THIS VERSION
This version contains no in-app purchases and no payment flow. Retreat pages
show details and pricing for information; the call to action opens an email
enquiry to our team. Bookings are handled offline by our staff.

CONTENT NOTE
"Coming soon" on the Somatic, Breathwork and Meditation cards is intentional:
those guided audio/video tracks are being recorded and will be enabled from the
server. The Journal, Exercises, Recipes and Massage sections are complete and
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
