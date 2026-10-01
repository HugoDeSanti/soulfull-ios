# Soulfull Gatherings — Design System (HTML mirror)

A faithful HTML/CSS recreation of the SwiftUI app, built so the UX team can edit
the design in **Claude Design** (claude.ai/design) and the changes translate
**1:1 back into the codebase**. This is a *mirror*, not the build — the iOS app
ships from `SoulfullGatherings/` and never imports anything here.

## The round-trip workflow

```
  Swift app  ──(this mirror)──▶  Claude Design  ──(UX edits)──▶  back to Swift
  Theme.swift                    tokens.css                       Theme.swift
  Components.swift               app.css                          Components.swift
  Feature views                  screens/*.html                   Feature views
```

1. **You push** this bundle to a Claude Design project (already done — see below).
2. **UX team edits** in the browser: nudge a color, retype copy, re-space a card,
   try a new layout on a screen.
3. **You pull their changes** (`DesignSync get_file`) in a Claude Code session and
   ask Claude to "port the Claude Design changes back to Swift." Because the
   mapping is 1:1, most edits are mechanical.

## How it maps to the codebase

| Design System file        | Swift source                          | What lives there |
|---------------------------|---------------------------------------|------------------|
| `shared/tokens.css`       | `Core/DesignSystem/Theme.swift`       | Colors, gradients, radii, type — one CSS var per `Theme.*` constant |
| `shared/app.css`          | `Core/DesignSystem/Components.swift`, `BottomNav.swift`, `OnboardingView.swift`, `PracticeShared.swift`, `Features/Auth/AppleSignInButton.swift` | Buttons, glass, chips, option cards, nav, steps, the Apple button, progress rule / continue card / streak |
| `shared/frame.css`        | (presentation only)                   | iPhone shell + iOS status bar — not part of the app |
| `foundations/*.html`      | `Theme.swift`                         | Swatch / type / gradient reference sheets |
| `components/*.html`       | `Components.swift` et al.             | One card per reusable view |
| `screens/*.html`          | `Features/**`                         | One card per screen |

### Token map (the important one)

Every variable in `tokens.css` is the sRGB conversion of a `Theme.swift` color
(stored there as RGB 0–1). Change a value in Claude Design → change the matching
constant in `Theme.swift`:

| CSS var | Theme.swift | Value |
|---|---|---|
| `--bg` | `Theme.bg` | `#0B0C07` |
| `--bg-deep` | `Theme.bgDeep` | `#10120A` |
| `--surface` | `Theme.surface` | `#15170D` |
| `--ink` | `Theme.ink` | `#F5F3E8` |
| `--ink-soft` | `Theme.inkSoft` | `#C9C5B0` |
| `--muted` | `Theme.muted` | `#7A7663` (on glass only — see below) |
| `--ink-on-photo` | `Theme.inkOnPhoto` | `rgba(245,243,232,0.92)` (ink @ 0.92) |
| `--accent` | `Theme.accent` | `#3E4315` |
| `--accent-soft` | `Theme.accentSoft` | `#77803B` |
| `--honey` | `Theme.honey` | `#E5C766` |
| `--card-radius` | `Theme.cardRadius` | `22px` |
| `--pill-radius` | `Theme.pillRadius` | `999px` |

> Theme.swift stores colors as RGB 0–1. To go from a new hex back to Swift:
> `R/255, G/255, B/255`. e.g. `#E5C766` → `Color(red: 0.898, green: 0.780, blue: 0.400)`.

### Type over photography

Most screens lay their header straight on a photo, and a photo backdrop is at
its lightest exactly where that header sits. One rule covers it everywhere —
change it in both places or the mirror drifts:

| Where | CSS | Swift |
|---|---|---|
| Header band darkening | `.top-scrim` (after `.vignette`) | `PhotoBackdrop(topScrim:)`, default `0.45` over `340pt` |
| Status bar band (tab shell only) | `.statusbar--scrim` on `.statusbar` | `MainTabView.StatusBarScrim`: `Theme.bgDeep` 0.94 → 0.86 behind the clock, → 0 over a 14pt tail below the status bar |
| Text halo | `.on-photo` | `View.onPhoto()` |
| Eyebrow colour | `--ink-soft` | `Theme.inkSoft` |
| Subline colour / size | `--ink-on-photo` at 14px | `Theme.inkOnPhoto`, `Theme.body(14)` |

`--muted` / `Theme.muted` is for type on **glass or a solid surface** — over a
photo it sinks into the scrim. Type inside a card or on `--bg` needs none of
this; the surface is its own ground.

## What's faithful vs. approximated

- **Faithful:** colors, type scale, spacing, copy, layout, component anatomy, Geist.
- **Approximated (CSS can't do Metal):** the aurora shader is a layered CSS
  gradient drift; Liquid Glass is `backdrop-filter` blur; breathing/pulse are CSS
  keyframes. They read correctly but aren't pixel-identical to the SwiftUI shaders.
- **Fonts:** Geist loads from Google Fonts. The app ships the Geist TTFs in
  `Resources/Fonts/`.
- **Images:** downscaled copies of the real asset-catalog photos live in `assets/`.

## v1 App Store scope (affects several cards)

The 1.0 submission ships a narrower app than this mirror once showed. Keep the
mirror matching the **shipping** app; parked work stays under
`Screens · Parked (post-v1)`.

| Change | Mirror effect |
|---|---|
| **Instructor profiles** (2026-09-28) | A new card, `instructor-profile.html` (`Screens · Practice`), maps to `Features/Instructors/InstructorProfileView.swift`: the guide's photo blurred to a colour field behind a 112pt portrait (honey ring 6pt out, a breathing honey halo), title eyebrow and name, **Followers \| Following** (headline-28 numbers, compact and rounded down like presence), a "Followed by" line (≤3 overlapping 24pt faces — yours first once you follow — and at most two names), a 196pt honey **Follow** pill that becomes quiet glass "✓ Following", About, and the Library (digital retreats, sessions, then the credited Movement / Recipes / Journal prompts). **Guides are met on the pages of what they made, never on the Practice landing** (a Guides shelf was tried and removed the same day): `.guide-card` in `shared/app.css` (`GuideCard.swift` — "Your guide", 50pt face in a honey ring, name, what they teach, chevron) sits on `program-detail` (before The days), `exercise-detail` and `recipe-detail` (after the header) and `journal-detail` (at the foot, clear of the editor); `player` gets the compact `.guide-chip` (`GuideCredit`). Absent wherever the content names no guide. |
| **Gatherings tab; Programs → Digital Retreats** (2026-09-25) | `bottom-nav` is **six** items — Home · Gatherings · Digital Retreats · Practice · Community · You — and `.nav-item` is `flex: auto` (content-sized slots + an equal share of the spare, `NavBarLayout`), because six equal slots put "Digital Retreats" into "Gatherings". Gatherings (a folded-map glyph) is the retreats stack as a tab root: `retreats-stack` / `retreats-catalog` lose "‹ Back" and gain the bar, the bottom card sits 8pt above it. `home` gains the Digital Retreats shelf it was missing and ends on Upcoming gatherings — both shelves hand off to their tabs. Every member-facing "program" is now "digital retreat": `programs` (title, "More digital retreats"), `program-detail` (back label, "Start this digital retreat", "Leave this digital retreat"), the `Screens · Digital Retreats` group. File paths are unchanged, so each card syncs to the same place. |
| **Community tab added** (2026-09-22; the old Circle placeholder — cut under Guideline 4.2 — is gone, this is its real successor) | `bottom-nav` is **five** items — Home · Programs · Practice · Community · You. `community.html` moved to `Screens · Tabs` and is the live feed: `AvatarView` (photo, or the initial on one of five id-picked tones), the All \| Friends scope toggle (a cream lens on glass, BottomNav's physics), the Friends button with a request badge, and `ActivityRow` ("Name practiced Title" + track · time) grouped Today / Yesterday / Earlier. `friends.html` is the pushed Friends screen (search by name, Requests / Sent / Friends with honey-fill primary pills). **Likes (same day):** each row carries a `LikeButton` — heart + count on a glass capsule, honey when yours, count-only on your own line — and the header a bell with an unread badge; `notifications.html` is the pushed list ("Alma G. liked your Morning Mobility practice", unread rows honey-dotted for the visit). A one-time **push prompt card** ("Hear when someone likes your practice" — Turn on / Not now) sits between the controls and the feed for a member who has never been asked. `profile.html` gains the 92pt avatar with a camera badge in place of the logo, and a Community section with the "Share my practice" toggle. Journal prompts never appear in the feed. |
| **Presence** (2026-09-23) | `PresenceBadge.swift` → `.presence` in `shared/app.css`: up to three overlapping 20pt faces (friends first) + "75.7k present" in `--ink-soft` body 12 medium. On practice rows (`practice-list.html`), recipe/exercise/journal detail (`recipe-detail.html`), program cards (`programs.html`, Home's shelf) and the program hero (`program-detail.html`). Absent below 3 people; journal prompts show the count with no faces. |
| **Programs tab added** | A fourth tab of self-paced, multi-day journeys — three new cards in `Screens · Programs`, and a "Day N is open" card on `home`. Free to browse, free to join, but joining needs an account (`AccountGate`), which is why `program-detail` is readable end to end while its CTA is the gate. |
| **Reservations off, Stripe dependency dropped** | `retreat-detail` CTA reads **"Request a place"** and opens `retreat-enquiry` (the retreat application form), with no other state: there is no client-side checkout left to push to. `retreat-checkout` is **deleted** from the mirror along with `RetreatCheckoutView.swift` and `PaymentService.swift`; recover both from git history if payments return. The Mallorca post-purchase cards (hub, to-dos, packing, guides) stay — they are trip logistics, not payment. |
| **No offline fallback for retreats** | The app no longer substitutes sample retreats when a fetch fails — it renders an explicit *"No internet connection"* or *"Couldn't load retreats"* state instead (Guideline 2.1(a): placeholder content must be scrubbed). **Not modelled here**: this mirror shows happy-path screens only, and has never carried error, empty or offline states — `ConnectionBanner` has no card either. If the UX team wants to design these, they are `RetreatsLoadFailure` in `RetreatsViewModel.swift` (a two-line card on `home`, a full-screen state on `retreats-stack`). |
| **Catalog photos come from Storage** | Retreat photography is fetched from the public `retreat-images` bucket, not bundled, so a new retreat needs no release. While a photo loads — or if it fails — the app paints a quiet two-stop gradient (`Theme.surface` → `Theme.bgDeep`) rather than a blank. **Not modelled here**, like the other loading states; the mirror shows loaded screens. |
| **Practice media tracks gated** | Somatic Exercises / Breathwork / Meditation carry a `SOON` badge, read "Coming soon", and are dimmed (`.pcard--soon`) until the `practice_sessions` table is seeded. |
| **Practice sections renamed, Personal Massages removed** | The Somatic track reads **"Somatic Exercises"**, the Exercises section reads **"Movement"** (`exercise-detail`'s back bar and card name follow), and the Personal Massages section is gone: `massage-detail.html` and `assets/practice-massage.jpg` are **deleted**, not parked. Home's Anxious and Tender mood chips used to point there and now point at Movement and Journal. The `massage` content kind is gone from Swift and from the DB check constraint too (migration 0012) — safe only because the app has no users yet and so no play history to strand. |
| **Legal links added** | `profile` gains a Privacy · Terms · Support row. |
| **The You tab keeps your practice** (2026-09-18) | `profile` becomes a scrolling page: four glass stat tiles (current streak — honey-tinted while alive — best streak, classes taken, minutes practiced), then **Digital retreats** (programs in progress, then completed) and **In-person retreats** (paid bookings whose retreat has ended), then the account actions. It maps to `Features/Profile/ProfileView.swift` (renamed from `ProfilePlaceholder`). A **guest** sees one "Keep it with you" card in place of all three sections, and each section's empty state is described in comments on the card rather than drawn. The card's `bottom-nav` is now four items, too; it was still three. |
| **No AI anywhere** | The app has no AI companion or chat and none is planned. `mallorca-chatbot` is **deleted** (it was a live `window.claude.complete` prototype), the hub's wide tile now opens an email to the team instead of a chat, and the third welcome slide — "Soul AI · Meet Soul, your companion through the journey" — is gone from `WelcomeView`. **Don't reintroduce an assistant card**: shipping UI that advertises an AI the app doesn't have is a metadata-accuracy rejection, and it ran on every first launch. |

## Accounts are just-in-time (affects the account card)

An account is **not** required to browse. `AppState` routes to the tabs on the
onboarding answers alone; `AccountGate` raises the account sheet only when a
guest opens an actual practice, then replays the tap they were making.

| Change | Mirror effect |
|---|---|
| **Sign in with Apple first** | `account` leads with a single `.social-btn` pill, then an `.or-rule`, then the email form. It sits at the native Sign in with Apple metrics (54px white capsule, 19px **system** font) — deliberately not the Geist `sg-btn` scale, because Apple's control can't be restyled. |
| **Confirmation is a code, not just a link** | A second card, `account-confirm`, is the state after "Create account" when Supabase email confirmation is on. It leads with a **code field** (one wide field, not a row of boxes — iOS one-time-code autofill targets a single field, and the digit count is the project's `mailer_otp_length`, currently 6) because the emailed *link* can only complete on the iPhone that signed up. Below it: Confirm email · Send a new code (60s cooldown = `smtp_max_frequency`) · Use a different sign-in. |
| **The sheet arrives mid-tap** | Its subtitle has to justify the interruption and promise the tap isn't lost, which is why the copy reads "we'll pick up exactly where you were" rather than a generic pitch. |
| **No onboarding gate card** | A full-screen `onboarding-account` card existed briefly on 3 September and was deleted the same day — a hard registration wall put the app in scope for App Store Guideline 5.1.1(i). The four `onboarding-*` question cards keep their `.onb-skip` control. |

> **Apple is the only third-party provider.** Google was built and then removed
> before shipping (2026-09-03) — don't re-add a second `.social-btn` to the
> account card without the Swift change to match.

## Card groups in Claude Design

`Overview` · `Foundations` · `Components` · `Screens · Welcome` ·
`Screens · Onboarding` · `Screens · Home` · `Screens · Digital Retreats` ·
`Screens · Retreats` · `Screens · Practice` · `Screens · Tabs` ·
`Screens · Parked (post-v1)`

Cards are indexed by the first-line `<!-- @dsCard group="…" name="…" -->` marker
in each HTML file.

### Digital Retreats (`programs`, `program-detail`, `program-day`)

Self-paced, multi-day journeys — "programs" in the code and the files, "digital
retreats" to a member. Mapped to `Features/Programs/**` and
`Core/Services/ProgramStore.swift`; the full spec is
`docs/PLAN-digital-programs.md`.

**The one thing not to flatten when redesigning these.** A day can be
unavailable for two different reasons, and they need two different sentences:

| State | Copy | Why it is its own state |
|---|---|---|
| `open` | "Begin day 3" / "1 of 2 done — keep going" | Available now. |
| `opens(date)` | "Opens tomorrow" + moon glyph | The previous day is **finished**; the calendar simply hasn't turned over. Day N+1 needs both its activities done *and* the local date to have moved past the day N was completed. |
| `awaitingPreviousDay` | "Finish day 2 first" + lock glyph | Nothing to wait for but the member. |
| `complete(date)` | "Completed Sep 15" + seal | Latched forever. |

Collapsing the middle two into one "Locked" chip is the obvious tidy-up and it
is wrong — "come back tomorrow" and "you're not done yet" send someone to
completely different actions. `ProgramDayState` in `Models.swift` carries all
four cases for exactly this reason.

Note also that **the day opens at local midnight but the notification fires at
08:00**. That gap is deliberate (`ProgramNotifications`), so a card promising
"opens tomorrow" and a notification arriving mid-morning are consistent, not a
bug.

### The retreat application (`retreat-enquiry`)

`Screens · Retreats` carries the form the "Request a place" CTA opens. It is a
**mirror of the website's own "Join a retreat" form** — same questions, same
order, same option lists — because an application sent from the app and one
sent from the site are read side by side in the same inbox. In Swift the
question text lives in `RetreatEnquiry.Question` and is used by both the form
and the email body, so the two cannot drift; edit the copy on this card and it
has to change there, not in the view.

Reaching it requires an account — `retreat-detail`'s CTA raises `account`
first for a guest and opens the form once they are in. That is a gate on an
*action*, not on browsing, so the 5.1.1(i) argument above is unchanged. It is
there because the **Email question is shown, not asked**: the card renders it
on the same glass surface as every other answer, at `--ink-soft` with a lock,
because it is an answer already given rather than a field that has stopped
working. Don't restyle it into an editable field — the server takes the address
from the caller's token regardless of anything the app sends.

Two other things on the card are **not** free text to restyle:

- the four investment bands and the three decision answers are the retreat
  team's own answer labels (`RetreatEnquiry.Investment` / `.Decision`) —
  rewording one silently splits a report that groups applications by band;
- the retreat options are drawn from the live `retreats` catalog at runtime and
  preselected to the retreat the guest came from. The four on the card are
  illustrative, not a list to maintain.

Submit posts to the `send-retreat-enquiry` Edge Function, which emails the
answers to the team — so the button does have a **"Sending…"** state, and a
failure shows a glass banner under it (same anatomy as `account`'s error
banner) with every answer left in place. The confirmation afterwards is the
website's own thank-you message.

### Mallorca post-purchase set (warm-espresso)

`Screens · Retreats` includes the reserved-retreat flow: `mallorca-welcome`
(hub), `retreat-todos`, `packing` and `mallorca-guides`. These use the UX team's
**warm-espresso** dark direction —
terracotta / olive / gold on an espresso canvas, all-Geist — defined inline as a
per-card `.mb` palette (NOT in `tokens.css`, since it's retreat-specific). The
Swift app mirrors it in `Features/Retreats/PostPurchase/RetreatPalette.swift`.
The original **brochure-light** versions (cream / Cormorant / Pinyon) were kept
outside this tree in `docs/design-brochure-backup/` until 2026-09-07; recover
them with `git show d20e3f6:docs/design-brochure-backup/`. When porting back to
Swift, map the `.mb` tokens to `RetreatPalette` — don't reintroduce the light
palette or fold these into the global `Theme`.

## Run it locally

Any static server (relative paths to `shared/` and `assets/` must resolve):

```bash
cd design-system
python3 -m http.server 8080
# open http://localhost:8080/index.html
```

Open any file in `foundations/`, `components/`, or `screens/` to preview a single card.
