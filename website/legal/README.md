# Legal pages for soulfullgatherings.com

Three documents, each in two formats. Not part of the Xcode build — `project.yml`
only sources `SoulfullGatherings/` and `Resources/Fonts`, so nothing here needs
`xcodegen generate`.

> **Not legal advice.** These were written against what this repo actually does
> — verified in the code, not assumed — but they are published now, so a lawyer
> licensed in Texas should read all three, and especially the arbitration clause
> (Terms §17) and the refund table (Retreat policy §5). Money and waivers of
> rights are involved.

## What's here

| File | Slug | Covers |
|---|---|---|
| `privacy-policy.html` / `.md` | `/soulfull-privacy-policy` | App + website + retreat data, CCPA, other US states, UK/EEA |
| `terms-of-service.html` / `.md` | `/soulfull-terms-of-service` | App + website: accounts, licence, wellness disclaimer, Apple's required clauses, arbitration |
| `retreat-booking-policy.html` / `.md` | `/soulfull-retreat-policy` | Deposits, balances, cancellation windows, insurance, health, conduct, liability |

## Published

All three pages are live and were verified to return 200 on 2026-09-07:

| Document | URL |
|---|---|
| Privacy Policy | `https://www.soulfullgatherings.com/soulfull-privacy-policy` |
| Terms of Service | `https://www.soulfullgatherings.com/soulfull-terms-of-service` |
| Retreat Booking & Cancellation Policy | `https://www.soulfullgatherings.com/soulfull-retreat-policy` |

They are wired into the app through `SoulfullGatherings/Core/Services/LegalLinks.swift`
(`privacyPolicy`, `terms`, `retreatPolicy`, and `supportEmail` =
`info@soulfullgatherings.com`), surfaced as the You tab's
Privacy · Terms · Retreat policy · Support row and as two links in the
checkout fineprint.

Every placeholder in this directory is filled. The values were taken from the
published pages so the repo copy and the live pages say the same thing:
**Soulfull Gatherings**, 3001 Esperanza Crossing, 78758 Austin, Texas ·
`info@soulfullgatherings.com` · 30% deposit, balance at 60 days, 90 / 60–89 /
under-60 cancellation tiers, US$150 change and transfer fees, 24-month credit.

`grep -c 'class="todo"' *.html` prints 0 for all three.

## ⚠️ Re-publish all three pages

The files in this directory are ahead of what is live. Paste each one back into
its Squarespace page — four corrections, spread across all three documents:

1. **Governing law is now Texas.** The published Terms (§16–17) and Retreat
   policy (§17) said *"the laws of Spain"* and *"the courts of Madrid"*. They
   now say **Texas**, with **Travis County, Texas** as the arbitration venue.
2. **The contracting party is now the LLC.** The pages contracted as "Soulfull
   Gatherings", a trade name. All three now open with **"Soulfull Gatherings
   LLC, a Texas limited liability company"**, and the contact and copyright
   blocks match. This is what puts the liability cap and the arbitration clause
   in the hands of the entity that actually exists — the Apple Developer
   enrollment is an Organization, `SOULFULL GATHERINGS LLC`.
3. **The privacy policy has an effective date again.** The published page lost
   the "Last updated / Effective" line. It reads **September 7, 2026** here —
   change it if that is not the real publication date.
4. **The retreat policy's section numbering skipped XVIII.** The live page runs
   XVII (Governing law) → XIX (Contact). The source here numbers 01–18 in
   sequence, so a clean re-paste fixes it.

No app release is needed for any of this — `LegalLinks.swift` points at URLs
rather than shipping the text.

## App Store Connect

Set on app `6808027652` (verified 2026-09-07):

- **Privacy Policy URL** → `https://www.soulfullgatherings.com/soulfull-privacy-policy`
- **Support URL** → `https://www.soulfullgatherings.com/contact`

**Custom EULA: deliberately not set.** Apple's standard EULA applies. The
Terms of Service run ~15,700 characters and App Store Connect's
`agreementText` field caps at 10,000, so they cannot be pasted in whole, and
truncating a legal document to fit is worse than not setting one. Apple's
standard EULA plus your own Terms linked in-app is ordinary practice, and
§11 of the Terms already carries the schedule Apple requires, so the two do
not conflict on the points Apple cares about. Revisit only if you want a
condensed EULA written specifically for that field.

## Editing from here

`_shared.css` + `src/*.body.html` are the sources; run `./build.sh` to
regenerate the three top-level `.html` files. The `.md` files are maintained by
hand — if you change wording in one format, change it in the other. Then
re-publish the changed page to Squarespace (Code Block for the HTML, or a text
block for the Markdown) and the app needs no release, because
`LegalLinks.swift` points at URLs rather than shipping the text.

## Keeping them true

These documents make specific factual claims about the app. If any of the
following changes, the privacy policy is wrong until you update it:

| If you… | Update |
|---|---|
| Add any analytics or crash-reporting SDK | §1 "What we do not collect", §5, §6, §9 |
| Turn on `AppFeatures.paymentsEnabled` | §1 payment note — the "reservations are switched off" callout stops being true |
| Sync journal reflections to Supabase | §2 — the "never leaves your phone" promise is the strongest claim in the document, and the easiest to break by accident. Recording that a prompt was *opened* is already covered (§1, "your practice activity"); uploading a word of what was *written* is not |
| Change what `practice_plays` records, or start paying out on a new library | §1 "your practice activity", §4, and the deletion paragraph in §11 |
| Add a provider (email marketing, push, support desk) | §5 sharing table |
| Make the onboarding questions clinical | §1, plus `PrivacyInfo.xcprivacy` moves from `OtherDataTypes` to `Health` |
| Re-add Google sign-in | §5 sharing table |
