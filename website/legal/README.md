# Legal pages for soulfullgatherings.com

Three documents, each in two formats. Not part of the Xcode build — `project.yml`
only sources `SoulfullGatherings/` and `Resources/Fonts`, so nothing here needs
`xcodegen generate`.

> **These are drafts, not legal advice.** They were written against what this
> repo actually does — verified in the code, not assumed — but a lawyer licensed
> in your state should read all three before you publish, and especially before
> you publish the arbitration clause (Terms §17) and the refund table
> (Retreat policy §5). Money and waivers of rights are involved.

## What's here

| File | Publish at | Covers |
|---|---|---|
| `privacy-policy.html` / `.md` | `/privacy` | App + website + retreat data, CCPA, other US states, UK/EEA |
| `terms-of-service.html` / `.md` | `/terms` | App + website: accounts, licence, wellness disclaimer, Apple's required clauses, arbitration |
| `retreat-booking-policy.html` / `.md` | `/retreat-policy` | Deposits, balances, cancellation windows, insurance, health, conduct, liability |

Sources: `_shared.css` + `src/*.body.html`. **Edit those, then run `./build.sh`** —
the top-level `.html` files are generated and will be overwritten. The `.md`
files are maintained by hand; if you change wording in one format, change it in
the other.

## Before you publish — fill these in

Every placeholder is bracketed. In the HTML they are also highlighted in honey
(`<span class="todo">`), so an unfilled one is visible on the page. When you are
done, `grep -c 'class="todo"' *.html` should print `0` for all three.

**Identity — appears in all three documents**

- [ ] `[Legal entity name]` — the registered name that contracts with guests (×9)
- [ ] `[Street address]`, `[City, State ZIP]` — a real mailing address. Required
      by CCPA, and App Store Connect reviewers do look for one.
- [ ] `[State]`, `[County, State]` — governing law and arbitration venue.
      **This was the one question left unanswered.** Use the state where the
      entity is formed or has its principal place of business.
- [ ] `[Month D, YYYY]` — last-updated and effective dates (×6). Use the day you
      actually publish, not today.
- [ ] `[YYYY]` — copyright year

**Contact addresses** — these can all be the same inbox, but it must be one
someone reads.

- [ ] `[privacy@yourdomain.com]` — privacy requests and deletion (×5)
- [ ] `[support@yourdomain.com]` — support and arbitration opt-out (×5)
- [ ] `[hello@yourdomain.com]` — retreat bookings and cancellations (×3)

**Retention — privacy policy §3 and §7**

- [ ] `[7]` years for booking/payment records · `[12 months]` for pre-retreat
      health info · `[3]` years for correspondence

**Notice period — terms §18**

- [ ] `[30]` days' notice before material changes take effect

**Retreat commercial terms — the whole of the booking policy**

- [ ] `[$X or X%]` deposit · `[60]` days for the balance · `[7]` days' grace on
      a late balance
- [ ] Cancellation table: `[90+]` / `[60–89]` / `[Under 60]` days, and the
      `[50%]` middle tier
- [ ] `[a $X administration fee]` for date changes · `[A $X transfer fee]` for
      passing a place on · `[90]` and `[30]` day windows for each
- [ ] `[45]` days' notice if we cancel · `[24 months]` credit validity ·
      `[with an added $X of value]`
- [ ] `[14]` days to pay a refund · `[28]` days to complain · `[14]` days to reply
- [ ] What's included: the four `[bracketed]` bullets in §2 ·
      `[US dollars]` · `[shared occupancy]` · `[bank transfer, on request]`

**One section to verify rather than fill in**

- [ ] **Privacy policy §6, "The website."** It describes soulfullgatherings.com
      as a hosted site (Squarespace, per the page source) with a mailing-list
      signup, and no analytics. Check that against what the site actually runs.
      If you add analytics, an advertising pixel, a chat widget or an embedded
      booking form, §6 **and** the sharing table in §5 both have to change.

**Delete the draft banner** at the top of each `.html` file (between the
`<!-- DELETE THIS BANNER BEFORE PUBLISHING -->` comments) and the equivalent
front matter in each `.md`.

## Publishing on Squarespace

The site is Squarespace, so you have two routes.

**Route A — Code Block (keeps the dark editorial look).** Create a page, add a
Code Block, and paste the entire `.html` file into it. Squarespace ignores the
`<!DOCTYPE>`, `<html>`, `<head>` and `<body>` wrappers and renders the rest.
Every CSS rule is scoped under `.sg-legal`, so it cannot leak into the rest of
your site — with one exception, clearly marked in the stylesheet:

```css
/* --- Page background. REMOVE THIS RULE if pasting into a Squarespace Code
       Block on a page that already sets its own background. ---------------- */
html, body { background: #0b0c07; margin: 0; }
```

Delete those two lines from the pasted copy if the page already has its own
background.

**Route B — normal text block (anyone on the team can edit it later).** Paste
the `.md` file into a Squarespace text block. It inherits the site's own
typography and loses the dark styling, but stays editable without touching code.

Either way, set the page URL slugs to `/privacy`, `/terms` and `/retreat-policy`
so the in-app links resolve, and add all three to the site footer.

## Wire them up

Once the pages are live:

1. **`SoulfullGatherings/Core/Services/LegalLinks.swift`** still carries three
   `TODO`s. `privacyPolicy` and `terms` already point at
   `https://soulfullgatherings.com/privacy` and `/terms` — confirm those resolve
   (note the live site answers on `www.`), and replace the placeholder
   `supportEmail`, which is currently `hello@soulfullgatherings.com` and is what
   every "Request a place" enquiry opens against. There is no constant for the
   retreat policy yet; add one if you want to link it from checkout.
2. **App Store Connect → App Privacy** — the Privacy Policy URL must be the live
   `/privacy` page, and the answers there must match both this policy and
   `SoulfullGatherings/PrivacyInfo.xcprivacy`. A mismatch between the three is a
   review flag.
3. **Squarespace footer** — link all three.

## Keeping them true

These documents make specific factual claims about the app. If any of the
following changes, the privacy policy is wrong until you update it:

| If you… | Update |
|---|---|
| Add any analytics or crash-reporting SDK | §1 "What we do not collect", §5, §6, §9 |
| Turn on `AppFeatures.paymentsEnabled` | §1 payment note — the "reservations are switched off" callout stops being true |
| Sync journal reflections to Supabase | §2 — the "never leaves your phone" promise is the strongest claim in the document, and the easiest to break by accident |
| Add a provider (email marketing, push, support desk) | §5 sharing table |
| Make the onboarding questions clinical | §1, plus `PrivacyInfo.xcprivacy` moves from `OtherDataTypes` to `Health` |
| Re-add Google sign-in | §5 sharing table |
