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
| **Circle tab cut** (Guideline 4.2 — a primary tab advertising unbuilt features) | `bottom-nav` is **three** items everywhere: Home · Practice · You. `community.html` moved to `Screens · Parked (post-v1)`. |
| **Reservations off, Stripe dependency dropped** | `retreat-detail` CTA reads **"Request a place"** (opens a support email) and has no other state — there is no client-side checkout left to push to. `retreat-checkout` is **deleted** from the mirror along with `RetreatCheckoutView.swift` and `PaymentService.swift`; recover both from git history if payments return. The Mallorca post-purchase cards (hub, to-dos, packing, guides) stay — they are trip logistics, not payment. |
| **Practice media tracks gated** | Somatic / Breathwork / Meditation carry a `SOON` badge, read "Coming soon", and are dimmed (`.pcard--soon`) until the `practice_sessions` table is seeded. |
| **Legal links added** | `profile` gains a Privacy · Terms · Support row. |
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
`Screens · Onboarding` · `Screens · Home` · `Screens · Retreats` ·
`Screens · Practice` · `Screens · Tabs` · `Screens · Parked (post-v1)`

Cards are indexed by the first-line `<!-- @dsCard group="…" name="…" -->` marker
in each HTML file.

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
