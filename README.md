# Soulfull Gatherings — iOS (SwiftUI)

A native iOS port of the Soulfull Gatherings prototype. Built with **SwiftUI**, **iOS 18**, **MVVM**, and zero third-party dependencies.

## What's inside

Core flow only, per spec:
- **Welcome** — splash → 3 explainer slides
- **Onboarding** — name → intention → nervous-system check-in → cadence → finish (4 steps + a closing slide)
- **Main** — home, with floating glass tab bar (Home, Practice, Circle, You)
- **Retreats** — Foodle-style stacked picker over crossfading photo backdrops
- **Retreat Detail** — full-bleed editorial detail with reserve CTA

Plus haptics on every meaningful tap, subtle screen transitions, persistent state via `@AppStorage`, and dark mode only.

## Project layout

```
SoulfullGatherings/
├── SoulfullGatheringsApp.swift     # @main entry
├── RootView.swift                   # Stage router (welcome → onb → main)
├── AppState.swift                   # Top-level ObservableObject (user, stage)
├── Theme.swift                      # Colors, fonts, gradients, materials
├── Haptics.swift                    # UIImpactFeedbackGenerator helpers
├── Models.swift                     # Retreat, Program, Circle, mock data
├── Components.swift                 # Buttons, glass cards, image backdrop
├── Welcome/
│   └── WelcomeView.swift
├── Onboarding/
│   ├── OnboardingView.swift         # Container + shell
│   ├── OnboardingViewModel.swift
│   └── OnboardingSteps.swift        # Name / Intention / State / Frequency / Finish
├── Main/
│   ├── MainTabView.swift            # Tab routing + floating nav
│   └── BottomNav.swift              # Custom glass tab bar
├── Home/
│   ├── HomeView.swift
│   └── HomeViewModel.swift
├── Retreats/
│   ├── RetreatsStackView.swift
│   ├── RetreatsViewModel.swift
│   └── RetreatDetailView.swift
└── Placeholders.swift               # Library / Community / Profile stubs
```

Images live in `Resources/` and need to be added to your Xcode asset catalog (see step 3 below).

## Setup in Xcode (5 minutes)

1. **Create the project.** In Xcode → File → New → Project → iOS → **App**.
   - Product Name: `SoulfullGatherings`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Minimum Deployments: **iOS 18.0**
   - Uncheck Core Data / Tests if you want a lean start.

2. **Replace the default sources.** Delete the auto-generated `ContentView.swift` and `SoulfullGatheringsApp.swift`. Drag the entire `SoulfullGatherings/` folder from this repo into your Xcode project navigator — check **"Create groups"** and **"Copy items if needed"**.

3. **Add the images.** Open `Assets.xcassets`. Drag the contents of `Resources/Images/` into the catalog (or create an Image Set for each name listed below). Names must match exactly:
   - `soulfull-logo-white`
   - `welcome-bg`, `onb-bg`, `home-bg`, `finish-bg`
   - `retreat-mallorca`, `retreat-kyoto`, `retreat-sedona`, `retreat-chamonix`, `retreat-bali`, `retreat-lapland`, `retreat-dolomites`

4. **Lock to dark mode.** In `Info.plist` (or Project → Info) add **User Interface Style = Dark**. This matches the design's dark-only intent and keeps system materials looking right.

5. **Build & run** to your iPhone (iOS 18+) or the iOS 18 simulator. Press ⌘R.

## Architecture notes

- **MVVM with `ObservableObject`.** Each major screen has its own `ViewModel` (e.g. `HomeViewModel`, `RetreatsViewModel`, `OnboardingViewModel`). `AppState` is the only app-wide store, injected via `.environmentObject`.
- **Persistence is `@AppStorage`.** User name, completed-onboarding flag, intentions, etc. survive relaunch without a database.
- **Navigation is real.** Welcome/onboarding/main uses a stage enum on `AppState` with `transition(.opacity.combined(with: .move))`. Inside main, retreats push via `NavigationStack` so swipe-back works natively.
- **Glass = system materials.** `.ultraThinMaterial` and `.regularMaterial` give the frosted-card look for free, and they adapt correctly on iOS 18.
- **Haptics** are isolated in `Haptics.swift` — call `Haptics.tap()`, `Haptics.success()`, etc. from any view.

## What's *not* in this build (yet)

Per your spec — only the core flow is wired. The other tabs (Practice, Circle, You) show themed placeholder screens. Adding them is a copy-paste of the same patterns; ping me when you're ready and I'll extend.

## Tweaks you'll probably want

- **System font vs. New York for headlines.** I used `Font.custom("New York", size:)` (which falls back to the system serif on iOS) to echo the Instrument Serif. If you want a stronger serif, drop a TTF into the project and switch the `Theme.headline` font.
- **Real backend.** Models are simple structs marked `Identifiable` + `Hashable`. Swap the `static let mock` arrays for an `async` fetch and you're done.
- **Sign-in.** Currently any "Begin" routes through. Add `AuthenticationServices` + Sign in with Apple where `RootView` chooses between welcome and main.
