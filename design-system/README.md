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
| `shared/app.css`          | `Core/DesignSystem/Components.swift`, `BottomNav.swift`, `OnboardingView.swift`, `PracticeShared.swift` | Buttons, glass, chips, option cards, nav, steps |
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
| `--muted` | `Theme.muted` | `#7A7663` |
| `--accent` | `Theme.accent` | `#3E4315` |
| `--accent-soft` | `Theme.accentSoft` | `#77803B` |
| `--honey` | `Theme.honey` | `#E5C766` |
| `--card-radius` | `Theme.cardRadius` | `22px` |
| `--pill-radius` | `Theme.pillRadius` | `999px` |

> Theme.swift stores colors as RGB 0–1. To go from a new hex back to Swift:
> `R/255, G/255, B/255`. e.g. `#E5C766` → `Color(red: 0.898, green: 0.780, blue: 0.400)`.

## What's faithful vs. approximated

- **Faithful:** colors, type scale, spacing, copy, layout, component anatomy, Geist.
- **Approximated (CSS can't do Metal):** the aurora shader is a layered CSS
  gradient drift; Liquid Glass is `backdrop-filter` blur; breathing/pulse are CSS
  keyframes. They read correctly but aren't pixel-identical to the SwiftUI shaders.
- **Fonts:** Geist loads from Google Fonts. The app ships the Geist TTFs in
  `Resources/Fonts/`.
- **Images:** downscaled copies of the real asset-catalog photos live in `assets/`.

## Card groups in Claude Design

`Overview` · `Foundations` · `Components` · `Screens · Welcome` ·
`Screens · Onboarding` · `Screens · Home` · `Screens · Retreats` ·
`Screens · Practice` · `Screens · Tabs`

Cards are indexed by the first-line `<!-- @dsCard group="…" name="…" -->` marker
in each HTML file.

## Run it locally

Any static server (relative paths to `shared/` and `assets/` must resolve):

```bash
cd design-system
python3 -m http.server 8080
# open http://localhost:8080/index.html
```

Open any file in `foundations/`, `components/`, or `screens/` to preview a single card.
