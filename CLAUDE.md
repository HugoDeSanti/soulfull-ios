# Soulfull Gatherings — iOS App

SwiftUI iOS app for a wellness retreat and community platform. Dark, editorial aesthetic throughout. All data is currently mock; no backend or network layer exists.

**Minimum deployment target: iOS 18.** Always use the latest Swift and SwiftUI idioms — `@Observable` over `ObservableObject`, `@Environment` over `@EnvironmentObject`, `@State` over `@StateObject`/`@ObservedObject`, typed throws, `NavigationStack` with typed `Route` enums, etc. Do not reach for deprecated patterns for compatibility — there is no older OS to support.

## Build & Run

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` from `project.yml`.

```bash
# Regenerate the Xcode project after editing project.yml
xcodegen generate

# Open in Xcode
open SoulfullGatherings.xcodeproj
```

Build and run via Xcode (⌘R). Target: iPhone, iOS 18+. Portrait only.

## Architecture

**Pattern:** MVVM with SwiftUI. Each screen has a paired `ViewModel` (`@MainActor final class … ObservableObject`). Global app state lives in `AppState`, injected as an environment object from the root.

**Stage routing:** `AppState.stage` drives the top-level switch in `RootView`:
```
welcome → onboarding → main
```
Stage transitions are animated and persisted via `@AppStorage("sg.hasOnboarded")`.

**Navigation within Main:** `MainTabView` hosts four tabs. The Home tab wraps its content in a `NavigationStack` with typed `Route` enum values so `RetreatsStackView` and `RetreatDetailView` push correctly with native swipe-back.

## File Map

```
SoulfullGatherings/
├── SoulfullGatheringsApp.swift   # @main entry, creates AppState, forces dark mode
├── AppState.swift                # Global state: stage routing + persisted user prefs
├── RootView.swift                # Stage switcher (welcome/onboarding/main)
├── Models.swift                  # All data models + mock data (Retreat, Program, etc.)
├── Theme.swift                   # Brand colors, gradients, typography helpers
├── Components.swift              # Shared UI: SGPrimaryButton, GlassCard, PhotoBackdrop, etc.
├── Haptics.swift                 # Thin UIKit haptic wrapper (tap/bump/select/success)
├── Placeholders.swift            # Empty states for Practice, Circle, Profile tabs
│
├── Welcome/
│   └── WelcomeView.swift         # Splash + 3 explainer slides → routes to onboarding
│
├── Onboarding/
│   ├── OnboardingView.swift      # 4-step flow + finish screen; all step sub-views inline
│   └── OnboardingViewModel.swift # Step state, validation, next/back, commit to AppState
│
├── Home/
│   ├── HomeView.swift            # Main dashboard: greeting, moods, ritual, retreats, circles
│   └── HomeViewModel.swift      # Greeting logic, mood selection, mock data surfaces
│
├── Retreats/
│   ├── RetreatsStackView.swift   # Foodle-style scrolling name stack with crossfading backdrop
│   ├── RetreatsViewModel.swift   # Active retreat index + haptics
│   └── RetreatDetailView.swift   # Editorial full-bleed detail + Reserve button
│
└── Main/
    ├── MainTabView.swift         # Tab container + HomeRoot NavigationStack
    └── BottomNav.swift           # Custom floating glass tab bar
```

## Design System

All brand values live in `Theme.swift`. Use `Theme.*` constants — never hardcode colors or font sizes.

| Token | Usage |
|---|---|
| `Theme.bg` | Near-black canvas (default background) |
| `Theme.ink` | Warm cream — primary text |
| `Theme.inkSoft` | Muted cream — secondary text |
| `Theme.muted` | Tertiary / metadata text |
| `Theme.accent` | Olive-green brand accent |
| `Theme.honey` | Amber glow for selected states |
| `Theme.line` | `white.opacity(0.10)` hairline |
| `Theme.headline(_:)` | Serif font (NY/system serif) |
| `Theme.body(_:)` | SF Pro |
| `Theme.eyebrow(_:)` | Small tracked caps |

**Glass surfaces:** Use `.ultraThinMaterial` + `white.opacity(0.14)` stroke. `GlassCard` wraps this pattern.

**Photo backdrops:** Use `PhotoBackdrop(imageName:blur:darken:)` — handles solid floor, blur, saturation, and vignette.

## Key Conventions

- `@MainActor` on all ViewModels.
- Haptics are mandatory on every interactive tap: `Haptics.tap()` for secondary, `Haptics.bump()` for primary CTAs.
- Navigation is value-based (`NavigationStack` + typed `Route` enums), not `NavigationLink` with destinations.
- All onboarding answers are validated before `canAdvance` returns `true`; never allow advancing with empty state.
- Mock data is defined as static `.mock` or `.all` properties on model types in `Models.swift`.
- `@AppStorage` keys are prefixed `sg.` (e.g., `sg.hasOnboarded`, `sg.userName`).

## Current State

- **Implemented:** Welcome flow, Onboarding (4 steps + finish), Home dashboard, Retreats stack, Retreat detail.
- **Placeholder (unbuilt):** Practice tab (Library), Circle tab (Community), You tab (Profile) — each shows a branded empty state.
- **No backend:** All content is mock data. No networking, auth, or persistence beyond `UserDefaults`.
- **No tests:** No test targets exist yet.

## Resources

Images live in `Resources/Images/` and are referenced by name (e.g., `"retreat-mallorca"`, `"home-bg"`, `"soulfull-logo-white"`). They must also be added to the asset catalog in Xcode for `Image(_:)` to find them.
