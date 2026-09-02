# App Review notes — Soulfull Gatherings 1.0

Paste the **Review notes** block below into App Store Connect → your build →
*App Review Information*. Everything above it is context for you, not Apple.

---

## Why this version needs almost no reviewer setup

v1 ships as a browsable wellness catalog and practice library:

- **No account is required.** The app opens an anonymous Supabase session at
  launch, so a reviewer sees the entire app without signing in.
- **Nothing is purchasable.** `AppFeatures.paymentsEnabled` is `false`, so the
  Stripe rail is unreachable. There is no demo account to provide, no seeded
  booking, and no third-party payment sheet to justify.
- **No third-party or social login**, so Guideline 4.8 (Sign in with Apple) does
  not apply. Account creation is optional email/password only.
- **Account deletion** is in-app under the You tab (Guideline 5.1.1(v)).

The optional account is worth exercising, because it is the only place the app
collects personal data. Either let the reviewer create their own, or supply a
test account below.

## Accounts and identifiers

| | |
|---|---|
| **Apple Developer account** | `app@soulfullgatherings.com` |
| **Bundle ID** | `com.soulfullgatherings.app` |
| **Team ID** | set `DEVELOPMENT_TEAM` in `Config/Secrets.xcconfig` (gitignored) |

> `app@soulfullgatherings.com` is the **developer account**, not necessarily the
> customer support address. `LegalLinks.supportEmail` is currently the
> placeholder `hello@soulfullgatherings.com` and is what users see in the app —
> it is the Support link in the You tab and the destination of every "Request a
> place" enquiry. Point it at whichever inbox is actually monitored.

## Before you submit — check each of these

- [ ] `LegalLinks.privacyPolicy` and `LegalLinks.terms` point at **live, public**
      pages, and the same privacy URL is entered in App Store Connect.
      A privacy policy URL that 404s is an automatic rejection.
- [ ] `LegalLinks.supportEmail` is a monitored inbox — it is both the Support
      link in the You tab and the destination of every "Request a place" enquiry.
- [ ] The `retreats` table contains only retreats that have **not yet ended**.
      The app filters on `end_date >= today`, so a stale catalog shows as empty
      rather than wrong — but an empty catalog reads as a broken app.
- [ ] If you seeded `practice_sessions`, open each track once on a device and
      confirm the media actually plays from the `practice-media` bucket.
- [ ] Privacy nutrition labels in App Store Connect match
      `SoulfullGatherings/PrivacyInfo.xcprivacy`.
- [ ] If you seeded `programs` (`0006_programs.sql`), the Digital Retreats shelf
      appears on Home. Until then it is hidden by design — not a bug.

## If you turn reservations on before submitting

Flipping `AppFeatures.paymentsEnabled` to `true` re-adds three review
obligations. Do not ship it without all three:

1. **A demo account with a paid booking already seeded.** A reviewer cannot
   complete a live charge, so without this the entire post-purchase experience
   is invisible and reads as unfinished.
2. **The Stripe justification** (paragraph provided below).
3. **Curated post-purchase content for every reservable retreat.** Today only
   Mallorca has it; any other retreat lands on empty Packing and Guides screens.

---

## Review notes — paste this into App Store Connect

```
Soulfull Gatherings is a wellness retreat and practice app.

NO SIGN-IN REQUIRED
The app opens directly into full functionality — browsing upcoming in-person
retreats and the practice library — without an account. Creating an account is
optional and only used to save your preferences.

TEST ACCOUNT (optional)
Only needed to review the account flows (create / sign in / delete).
  Email:    <fill in>
  Password: <fill in>
Account deletion is available in-app: the "You" tab → Delete account.

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
with the test account above — it already has a confirmed reservation.
```
