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

1. **You push** changed cards with `/sync-design push` (incremental, never the whole bundle).
2. **UX team edits** in the browser: nudge a color, retype copy, re-space a card,
   try a new layout on a screen.
3. **You pull their changes** with `/sync-design pull` in a Claude Code session,
   which ports them back to Swift. Because the mapping is 1:1, most edits are
   mechanical.

## How it maps to the codebase

| Design System file        | Swift source                          | What lives there |
|---------------------------|---------------------------------------|------------------|
| `shared/tokens.css`       | `Core/DesignSystem/Theme.swift`, `Atmosphere.swift` | Colors, gradients, the atmosphere tones, hairline / space / motion, type — one CSS var per `Theme.*` constant |
| `shared/app.css`          | `Core/DesignSystem/Components.swift` (SGPrimaryButton, GlassCard, SectionLabel, GlyphButton, PhotoBackdrop), `SoulGlass.swift`, `Pressable.swift`, `Atmosphere.swift`, `BottomNav.swift`, `OnboardingView.swift`, `PracticeShared.swift`, `Features/Auth/AppleSignInButton.swift`, `Features/Community/MemberSafety.swift` | Buttons, glass, the photo backdrop, the ritual card's atmosphere, chips, option cards, nav, steps, the Apple button, progress rule / continue card / streak / safety note, the member "⋯" menu |
| `shared/frame.css`        | (presentation only)                   | iPhone shell + iOS status bar — not part of the app |
| `foundations/*.html`      | `Theme.swift`                         | Swatch / type / gradient reference sheets |
| `components/*.html`       | `Components.swift` et al.             | One card per reusable view |
| `screens/*.html`          | `Features/**`                         | One card per screen |

### The direction: still

Since 2026-10-10 the app is still: near-white type over **each screen's own
photograph, which stays visible** (no black ground, no dark wash over it or
over the cards); **every corner square** (only a face, a dot and the player's
breath ring are round);
**hairlines and space instead of boxes** wherever a box only grouped text;
**still motion** — a press dims, things fade in and settle at breath pace,
nothing springs, squishes, bounces or zooms. Keep new cards inside that.

### Token map (the important one)

Every variable in `tokens.css` is the sRGB conversion of a `Theme.swift` value
(colours stored there as RGB 0–1). Change a value in Claude Design → change the
matching constant in `Theme.swift`:

| CSS var | Theme.swift | Value |
|---|---|---|
| `--bg` | `Theme.bg` | `#000000` (true black) |
| `--bg-deep` | `Theme.bgDeep` | `#090908` (the docked bar) |
| `--surface` | `Theme.surface` | `#10100E` |
| `--ink` | `Theme.ink` | `#F2F1ED` |
| `--ink-soft` | `Theme.inkSoft` | `#C9C7C1` |
| `--muted` | `Theme.muted` | `#7D7B76` (never on a photo — see below) |
| `--ink-on-photo` | `Theme.inkOnPhoto` | `rgba(242,241,237,0.92)` (ink @ 0.92) |
| `--accent` | `Theme.accent` | `#3E4315` (moss deep, the logo) |
| `--accent-soft` | `Theme.accentSoft` | `#7D8738` (moss light: switches, "complete") |
| `--ember` | `Theme.ember` | `#D08C5E` (the one warm mark; replaced honey) |
| `--danger` | `Theme.danger` | `#D95C54` (irreversible actions: Delete account) |
| `--line` / `--glass-border` / `--glass-border-high` | `Theme.line` / `.glassBorder` / `.glassBorderHigh` | white @ 0.10 / 0.12 / 0.22 |
| `--hairline` | `Theme.hairline` | `0.75` — every surface and ghost-button stroke |
| `--gutter` | `Theme.gutter` | `24` — the page margin |
| `--section-gap` | `Theme.sectionGap` | `64` — between a page's sections |
| `--header-gap` | `Theme.headerGap` | `40` — a tab's header to its first content, measured to what shows |
| `--ease-press` … `--ease-stage`, `--breath` | `Theme.Motion.*` | press .12s / release .5s / settle .6s / reveal 1.1s / stage 1.2s; breath 6s |
| `--atmos-<tone>-top/-mid/-low`, `--atmos-reach`, `--atmos-intensity` | `Atmosphere(tone:reach:intensity:)` | moss · ember · dusk · slate; used only by Home's ritual card (ember, reach 1.15, intensity 1) |

There are no radius tokens: `Theme.cardRadius` and `Theme.pillRadius` are gone.

> Theme.swift stores colors as RGB 0–1. To go from a new hex back to Swift:
> `R/255, G/255, B/255`. e.g. `#D08C5E` → `Color(red: 0.816, green: 0.549, blue: 0.369)`.

**Grounds.** Every tab and page sits on its own photo backdrop (`.photo` →
`.vignette` → `.top-scrim`, the first children of `.screen`, which stack behind
the content), blurred and darkened per screen exactly as its
`PhotoBackdrop(...)` in Swift, and the photo stays visible. The black
`.atmosphere` grounds that briefly replaced them read as a dark veil over the
app and were reverted the same day; `.atmosphere` survives only as Home's
ritual card wash. Glass (`.glass`, `.glass-card`) is a light frost with a
hairline, with no black wash, so the photo shows through it too.

### Type over photography

Most screens lay their header straight on a photo, and a photo backdrop is at
its lightest exactly where that header sits. One rule covers it everywhere —
change it in both places or the mirror drifts:

| Where | CSS | Swift |
|---|---|---|
| Header band darkening | `.top-scrim` (after `.vignette`) | `PhotoBackdrop(topScrim:)`, default `0.45` over `340pt` |
| Status bar fade (scrolled state only) | none: screens are drawn at rest, and nothing is drawn behind `.statusbar` (see the note in `app.css`) | `View.statusBarFade(fadeIn:reach:)` in `Components.swift`, on each scrolling screen's `ScrollView`: no effect at rest; over the first 36pt of scroll the content turns transparent behind the clock, eased back in over the status bar's last 22pt (+ `reach` under a pinned Back bar). A mask, never a band: nothing is drawn over the photo |
| Text halo | `.on-photo` | `View.onPhoto()` |
| Eyebrow colour | `--ink-soft` | `Theme.inkSoft` |
| Subline colour / size | `--ink-on-photo` at 14px | `Theme.inkOnPhoto`, `Theme.body(14)` |

`--muted` / `Theme.muted` is for type on **glass or a card** — over a photo it
sinks into the scrim, so text laid on a page (which is always on a photo)
uses `--ink-soft` instead. Type inside a card needs none of this; the surface
is its own ground.

## What's faithful vs. approximated

- **Faithful:** colors, type scale, spacing, copy, layout, component anatomy, Geist.
- **Approximated (CSS can't do Metal):** the player's aurora shader is a layered
  CSS gradient drift; glass's frost is a `backdrop-filter` blur; the
  ritual card's breath and the breathing/pulse loops are CSS keyframes. They read
  correctly but aren't pixel-identical to SwiftUI.
- **Fonts:** Geist loads from Google Fonts. The app ships the Geist TTFs in
  `Resources/Fonts/`.
- **Images:** downscaled copies of the real asset-catalog photos live in `assets/`.

## Keep the mirror matching the shipping app

The mirror shows what a member can reach in the current build, nothing parked.
`git log -- design-system` has the history of each card; these are the rules
that still bite when a card is edited:

- **Happy path only.** There are no error, empty, offline or loading states
  (`ConnectionBanner`, `RetreatsLoadFailure`, the gradient a photo paints while
  it loads). A guest's or an empty section's state is described in a comment on
  the card rather than drawn.
- **Six tabs:** Home · Gatherings · Digital Retreats · Practice · Community ·
  You. `.nav-item` is `flex: auto` (`NavBarLayout`), because six equal slots
  push "Digital Retreats" into "Gatherings".
- **"Program" is "digital retreat"** in every word a member reads. File names
  keep "program", so each card syncs to the same place.
- **Guides appear only on the pages of what they made:** `.guide-card` on
  `program-detail`, `exercise-detail`, `recipe-detail` and `journal-detail`,
  `.guide-chip` on `player`. Never on `practice-landing`.
- **Report and Block:** a `.member-menu` "⋯" sits beside every *other* member
  (`community`, `friends`, `notifications`), never on your own line. The Block
  confirmation is a system sheet with no card; its copy is in `community`'s
  header comment. The report reasons in `report-member` are the team's email
  labels and `report-member`'s strings, so change them together.
- **Presence** (`.presence`) is absent below 3 people, and journal prompts show
  a count with no faces. Journal prompts never appear in the feed.
- **Practice media tracks** with no rows are dimmed with a `SOON` badge
  (`.pcard--soon`).
- **Retreats:** the CTA reads "Request a place" and opens `retreat-enquiry`.
  There is no checkout card while payments are off.
- **No AI, anywhere.** Don't add an assistant or chat card: UI that advertises
  an AI the app doesn't have is a metadata-accuracy rejection.

## Accounts are just-in-time (affects the account card)

An account is **not** required to browse. `AppState` routes to the tabs on the
onboarding answers alone; `AccountGate` raises the account sheet only when a
guest opens an actual practice, then replays the tap they were making.

| Change | Mirror effect |
|---|---|
| **Sign in with Apple first** | `account` leads with a single `.social-btn`, then an `.or-rule`, then the email form. It sits at the native Sign in with Apple metrics (54px, 19px **system** font) — deliberately not the Geist `sg-btn` scale, because Apple's control can't be restyled; white behind it fills Apple's rounded corners in, so it reads square. |
| **Confirmation is a code, not just a link** | A second card, `account-confirm`, is the state after "Create account" when Supabase email confirmation is on. It leads with a **code field** (one wide field, not a row of boxes — iOS one-time-code autofill targets a single field, and the digit count is the project's `mailer_otp_length`, currently 6) because the emailed *link* can only complete on the iPhone that signed up. Below it: Confirm email · Send a new code (60s cooldown = `smtp_max_frequency`) · Use a different sign-in. |
| **Forgot password is a code too** | In sign-in mode a "Forgot password?" link (13px ink, underlined, trailing under the password field) opens two more states of the same sheet: `account-reset` (the address, carried over from the form → Send code, plus a line pointing Apple members back to Apple) and `account-reset-code` (the code field from `account-confirm` **and** a new-password field in one step → Set new password · Send a new code · Back to sign in). The copy never says whether the address has an account. The email has a code and no link (`supabase/templates/README.md`). |
| **What continuing agrees to** | Under the mode toggle, in both modes, a centered 12px `--muted` line: what other members see (first name, last initial, photo) and that continuing agrees to the Terms (which carry the community standards Guideline 1.2 asks for) and acknowledges the Privacy Policy. The two links are `--ink-soft`, not underlined. |
| **The sheet arrives mid-tap** | Its subtitle has to justify the interruption and promise the tap isn't lost, which is why the copy reads "we'll pick up exactly where you were" rather than a generic pitch. |
| **No onboarding gate card** | A registration wall at the end of onboarding falls under Guideline 5.1.1(i), so there is none. The four `onboarding-*` question cards keep their `.onb-skip` control. |

> **Apple is the only third-party provider.** Don't add a second `.social-btn`
> to the account card without the Swift change to match.

## Card groups in Claude Design

`Overview` · `Foundations` · `Components` · `Screens · Welcome` ·
`Screens · Onboarding` · `Screens · Home` · `Screens · Digital Retreats` ·
`Screens · Retreats` · `Screens · Practice` · `Screens · Tabs`

Cards are indexed by the first-line `<!-- @dsCard group="…" name="…" -->` marker
in each HTML file.

### Digital Retreats (`programs`, `program-detail`, `program-day`)

Self-paced, multi-day journeys — "programs" in the code and the files, "digital
retreats" to a member. Mapped to `Features/Programs/**` and
`Core/Services/ProgramStore.swift`; the rules are in `CLAUDE.md` → *Digital
programs*.

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
completely different actions. `ProgramDayState` in `Models/Program.swift` carries all
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
on the same square surface as every other answer, at `--ink-soft` with a lock,
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
failure shows square glass with an ember hairline under it (same anatomy as
`account`'s error banner) with every answer left in place. The confirmation afterwards is the
website's own thank-you message.

### Mallorca post-purchase set (warm-espresso)

`Screens · Retreats` includes the reserved-retreat flow: `mallorca-welcome`
(hub), `retreat-todos`, `packing` and `mallorca-guides`. These use the UX team's
**warm-espresso** dark direction —
terracotta / olive / gold on an espresso canvas, all-Geist, square and still like
the rest of the app (bare ← glyphs, hairline-ruled rows, square checkboxes, 2px
progress runs) — defined inline as a
per-card `.mb` palette (NOT in `tokens.css`, since it's retreat-specific). The
Swift app mirrors it in `Features/Retreats/PostPurchase/RetreatPalette.swift`.
When porting back to Swift, map the `.mb` tokens to `RetreatPalette`, and don't
fold them into the global `Theme`.

## Run it locally

Any static server (relative paths to `shared/` and `assets/` must resolve):

```bash
cd design-system
python3 -m http.server 8080
# open http://localhost:8080/index.html
```

Open any file in `foundations/`, `components/`, or `screens/` to preview a single card.
