# App Review notes: Soulfull Gatherings 1.0

Paste the **Review notes** block below into App Store Connect → the 1.0 version → *App Review Information → Notes*. Everything else in this file is context for us, not Apple.

> **Rewritten 2026-10-08** for the app as it is now: Community, Digital Retreats, guides, the in-app retreat application, and Report / Block (Guideline 1.2). The earlier versions (2026-09-03) described a practice-only app with an email enquiry. Don't restore them from git history.

---

## What the reviewer will meet

- **Browsing needs no account** (Guideline 5.1.1(i)): retreats, the brochure, every practice list, digital retreats, guide pages, and the Community feed.
- **An account is asked for at the moment someone reaches for something personal:**
  - opening a practice (it is recorded to their history and pays the guide)
  - starting a digital retreat
  - the Friends feed and screen
  - liking
  - following a guide
  - Block
  - reading and writing comments (they live on practice pages)
  - "Request a place" (the application's email is the account's)
- **The account sheet opens on "Create your account".** A reviewer with the demo credentials has to tap **"Already have an account? Sign in"** at the bottom. If they type the credentials into the create form instead, the error now ends "Already have an account? Sign in below." The notes say it as well.
- **User-generated content (Guideline 1.2).** Members see each other's names (first name + initial) and profile photos, finished practices, likes, and comments under a practice.
  - **"⋯" beside any other member** offers **Report** (reason + note, sent to the team, reviewed within 24 hours) and **Block** (they disappear from each other's Community and comments, and any friendship ends).
  - **"⋯" on every comment** offers **Report comment** and **Block**; on your own, **Delete**. A comment with a link or objectionable language is refused before it posts.
  - **You tab → Blocked members** lists blocks and unblocks.
  - **Names** with objectionable words show as "A member".
  - **The Terms** carry zero-tolerance community standards, which members agree to on the account sheet.
  - **Runbook:** `docs/MODERATION.md`.
- **Guide accounts (Guideline 2.3.1, disclosed so it isn't a hidden feature).** An account the team links to a guide sees an extra "Guide dashboard" card on the You tab: their reach, and their share of a monthly pool by time heard. The demo account is not a guide.
- **No purchases.** Retreats are real-world trips. "Request a place" sends an application to the team, who reply by email, and there is no payment code in the binary.
- **Notifications.** They are asked for in context only:
  - **Starting a digital retreat:** local reminders, on the morning the next day opens.
  - **A card on Community:** likes, which come by push.
- **Account deletion** (5.1.1(v)) is at the bottom of the You tab. For a Sign in with Apple account it also revokes the Apple grant.

## Before you submit: check each of these

**Backend for this build:**
- [x] **Migration `0028_member_safety.sql` is applied** (2026-10-08, after a dry run) and recorded in `schema_migrations`.
- [x] **`report-member` is deployed** (JWT verification on), using the existing `RESEND_API_KEY`. A test report was filed on 2026-10-08 and then dismissed. Check that its email ("Member report — Something else — App R.") reached info@.
- [ ] Someone watches info@ every day. **The 24-hour response is a promise in the app, the Terms and these notes.**

**Accounts:**
- [x] **The demo account exists** (2026-10-08): `appreview@soulfullgatherings.com`, "App Review", confirmed, not linked to any guide, with a name and onboarding answers (so a sign-in from Welcome lands on Home), enrolled in *Finding Ground*. Its accepted friend is `appreview.friend@soulfullgatherings.com` ("Demo Friend"). The passwords are in App Store Connect's review details and nowhere in the repo.
- [ ] **Give them real history, by using the app (nothing was invented):**
  - Signed in as the demo account, finish two or three practices, ideally on different days, so the You tab has numbers, and finish day 1 of Finding Ground.
  - Signed in as Demo Friend, finish a practice and like one of the demo's, so Friends and the bell have something to show.
- [ ] Sign in with the demo account once on a clean install, from Welcome **and** from the account gate.
- [ ] **Supabase Auth settings:**
  - Apple provider ON, with `com.soulfullgatherings.app` in *Client IDs*.
  - `soulfull://auth-callback` in Redirect URLs.
  - Anonymous sign-ins ON.
- [ ] **Sign in with Apple revocation, end to end on a real device:** sign in with Apple → You → Delete account → *Settings → Apple Account → Sign in with Apple* no longer lists Soulfull. A simulator can't prove this.

**Content (`CLAUDE.md` → Current state):**
- [ ] **The placeholder practice sessions and the five placeholder guides (AI-generated faces) are replaced by real ones (Guideline 2.1(a)).** The session blurbs literally say "A placeholder while the real sessions are recorded". Then update the NO AI paragraph below to match the truth.
- [ ] **The retreat catalog only holds real retreats, at real dates and prices.** The AI-generated Kyoto and Lapland covers are replaced.
- [ ] Brochure copy has no alcohol, tobacco or drug references (Guideline 2.3.6). The website's Chamonix page mentions wine and a sommelier, so keep those out.

**App Store Connect (filled 2026-10-08 except where unticked):**
- [x] Description, subtitle, keywords, promotional text, copyright, category (Health & Fitness / Lifestyle), marketing and support URLs, 7 screenshots at 6.9".
- [x] Price: free. Availability: every territory except China mainland, which needs an ICP filing.
- [x] Age rating: **13+**. The questionnaire is answered (user-generated content, health/wellness topics and social media are yes, everything else none), and the override is set to 13+ to match the Terms' minimum age.
- [ ] **EU Digital Services Act trader status** (Business → Compliance). The app isn't sold in the EU until it's declared.
- [x] **App Privacy answers** published by hand (2026-10-09), to match `SoulfullGatherings/PrivacyInfo.xcprivacy`: every type linked to the user and not used for tracking; App Functionality, plus Analytics on Product Interaction. There's no API for this, so any change to the manifest means editing them again.
- [ ] Content rights: "Does your app contain, show, or access third-party content?"
- [x] App Review contact, the notes block below, and the demo credentials, all in App Review Information (2026-10-08).
- [x] Build 1.0 (16) attached to the 1.0 version (2026-10-08).
- [x] The privacy policy and Terms are updated on the website (published 2026-10-09). They cover Community, photos, push, the application form, Report/Block and the community standards. The previous versions are backed up in `build/legal-drafts/live-backup-*.html`, which is gitignored.

## Creating the demo account

Sign-ups need email confirmation, so create it pre-confirmed in the Supabase dashboard: **Authentication → Users → Add user → Create new user**, tick **Auto Confirm User**. Then sign in once in the app, answer onboarding, finish a couple of practices on different days, start Finding Ground, and become friends with the second test account.

---

## Review notes: paste this into App Store Connect

```
Soulfull Gatherings: information about our in-person wellness retreats, a
library of guided practices, free self-paced "digital retreats", and a small
community feed.

NO ACCOUNT NEEDED TO BROWSE
After two intro slides and four optional questions, retreats, every practice
list, digital retreats, guide pages and the community feed are open to a guest.

DEMO ACCOUNT
  Email:    <fill in>
  Password: <fill in>
On the first launch, tap "I already have an account" on the welcome screen.
Later, the account sheet opens on "Create your account": tap "Already have an
account? Sign in" at its foot. The demo account is
enrolled in the digital retreat "Finding Ground", and has a friend (Demo
Friend) under Community -> Friends.

WHAT ASKS FOR AN ACCOUNT, AND WHY
Opening a practice, starting a digital retreat, Friends, likes, following a
guide, blocking someone, and "Request a place". Opening a practice records the
time spent to the member's history: it drives resume, streaks and
digital-retreat progress, and it is how we pay the guide who recorded it.
Journal reflections stay on the device. Sign in with Apple is offered first;
email and password is the alternative.

COMMUNITY AND COMMENTS: REPORT AND BLOCK (GUIDELINE 1.2)
Members appear as first name and initial, with an optional photo, beside the
practices they finish and the comments they leave under a practice (movement,
recipes, sessions). The "..." beside any other member, and on every comment,
offers Report (a reason and an optional note, sent to our team, reviewed
within 24 hours) and Block (they disappear from each other's Community and
comments, and any friendship ends). Your own comment's "..." offers Delete.
You -> Blocked members lists and unblocks. Names containing objectionable words
are not shown, and comments with links or objectionable language are refused. Members agree to our Terms, which include zero-tolerance
community standards, when they create an account. You -> "Share my practice"
turns sharing off.

DIGITAL RETREATS
Free. Days open one at a time: the next day opens on the calendar day after
the previous one is finished.

RETREATS
No purchases and no payment code in this version. "Request a place" opens an
application form that is sent to our team, who reply by email.

GUIDE ACCOUNTS
Accounts our team links to a guide also see a "Guide dashboard" card on the
You tab (people reached and their monthly earnings share). The demo account
is not a guide.

ACCOUNT DELETION
You tab -> bottom -> Delete account -> confirm. For Sign in with Apple
accounts we also revoke the Apple token.

NOTIFICATIONS
Requested only when starting a digital retreat (a local reminder when the next
day opens) or from a card on the Community tab (likes).

NO AI
The app has no AI features and no chatbot.

CONTACT
info@soulfullgatherings.com
```

## Stripe justification: only if reservations are enabled

Flipping `AppFeatures.paymentsEnabled` back on brings back three obligations:
- a demo account with a **paid booking already seeded** (a reviewer can't complete a live charge)
- the paragraph below
- curated post-purchase content for every reservable retreat (today only Mallorca has it)

```
PAYMENTS (Guideline 3.1.3(e): goods and services outside the app)
Reservations are for physical, in-person retreats at named real-world locations
on fixed calendar dates: travel, accommodation, meals and in-person coaching
delivered entirely offline. Under Guideline 3.1.3(e) these are goods and
services consumed outside the app, so payment is processed by Stripe rather than
in-app purchase. Nothing digital is unlocked by the payment; the post-purchase
screens are trip logistics (checklists, packing, scheduling a 1:1 with a guide
on site) for a trip the member is physically attending.

To review the reserved-retreat experience without completing a charge, sign in
with the demo account above. It already has a confirmed reservation.
```
