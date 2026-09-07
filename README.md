# Soulfull Gatherings — iOS (SwiftUI)

A native iOS app for a wellness retreat and community platform — dark, editorial, "quiet luxury" aesthetic throughout. Built with **SwiftUI**, **iOS 18+**, **Swift 6**, and an **MVVM + Observation** architecture. Backed by **Supabase** (PostgreSQL + Storage + Auth) and **Stripe** (retreat reservations).

> **`CLAUDE.md` is the deep architecture reference** — the full file map, backend schema, RLS gotchas, and conventions live there. This README is the get-it-building onboarding guide. For the design direction see [`docs/DESIGN.md`](docs/DESIGN.md); for backend deploy steps see [`supabase/functions/README.md`](supabase/functions/README.md); for the Claude Design mirror see [`design-system/README.md`](design-system/README.md).

## What's inside

- **Welcome** — splash (breathing logo) → 3 explainer slides → onboarding
- **Onboarding** — name → intention → nervous-system check-in → cadence → finish (4 questions + a closing slide)
- **Home** — dashboard: greeting, mood chips, ritual card, programs, circles, a retreat glimpse
- **Retreats** — viewport-aligned stacked name picker over crossfading photo backdrops → full editorial detail spread with a Reserve CTA (Stripe). Rich brochure stories render for retreats with curated `RetreatExperience` content (e.g. Mallorca).
- **Practice** — media categories (Somatic / Breathwork / Meditation) → session list → AVKit player, plus Journal prompts, Exercises, Recipes, and Personal Massages
- **Circle** / **You** — Community placeholder; You tab has real account UI (create / sign in / sign out / delete account) + onboarding status
- **Auth** — anonymous Supabase guest session on launch, upgradable in place to a permanent email/password account (Phase 1), with email-confirmation deep linking
- **Payments** — Stripe `PaymentSheet` for retreat reservations (Phase 2), wired end-to-end and verified in Stripe test mode

Plus mandatory haptics on every meaningful tap, a Metal-shader effect suite (grain / aurora / shimmer / dissolve / ripple, all Reduce-Motion-aware), real Liquid Glass on iOS 26+ (material fallback on 18–25), and dark mode forced app-wide.

## Tech stack

| Area | Choice |
|---|---|
| UI | SwiftUI, iOS 18 minimum, portrait-only, dark mode only |
| Language | Swift 6.0 (pinned in `project.yml`) |
| State | Observation framework — `@Observable @MainActor`, `@Environment`, `@State`. **No `ObservableObject` / `@Published` / `@AppStorage`.** |
| Navigation | `NavigationStack` with typed `Route` enums per tab root (value-based) |
| Project gen | [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the single source of truth |
| Backend | Supabase (Postgres + Storage + Auth; anonymous guests upgradable to email/password) |
| Payments | Stripe `StripePaymentSheet` via Supabase Edge Functions |
| Fonts | Geist (six weights, registered in `Info.plist`) — no serif/SF split, everything is Geist |
| Tests | None currently — the `SoulfullUITests` UI-test target was removed; no unit tests yet |

## Prerequisites

- **Xcode 16+** with the iOS 18 SDK (Metal toolchain required for the shaders)
- **XcodeGen** — `brew install xcodegen`
- A **Supabase** project (for real data/auth) and, for payments, a **Stripe** account. The app still runs without them: retreats and practice sessions fall back to mock data, but auth and Reserve need a live Supabase project.

## Build & run

```bash
# 1. Configure credentials (gitignored — never commit the real file)
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
#    then edit Config/Secrets.xcconfig and fill in:
#      SUPABASE_HOST     = your-project-id.supabase.co   (host only, no https://)
#      SUPABASE_ANON_KEY = your-anon-key
#    from Supabase Dashboard → Settings → API

# 2. Generate the Xcode project from project.yml
xcodegen generate

# 3. Open and run (⌘R) on an iPhone / iOS 18 simulator
open SoulfullGatherings.xcodeproj
```

**Regenerate `.xcodeproj` whenever you edit `project.yml`.** Everything under `supabase/` is *not* part of the Xcode build, so changing them needs no `xcodegen generate`.

> **Why XcodeGen?** The `.xcodeproj` is gitignored and generated. `project.yml` is the single source of truth for the target, Swift 6 / iOS 18 settings, bundle ID `com.soulfullgatherings.app`, SPM dependencies, the Geist font resources, the `soulfull://` URL scheme, and `Secrets.xcconfig` injection.

> **Stripe SPM source:** dependencies resolve from **`github.com/stripe/stripe-ios-spm`** (the slim, SPM-optimized distribution), *not* `stripe/stripe-ios` — the main repo's multi-GB history makes resolution extremely slow. Don't switch it back.

## Project layout

```
Config/                 # Secrets.xcconfig (gitignored) + .example template
Resources/Fonts/        # Geist .otf files (added as a resources build phase)
docs/DESIGN.md          # Design direction: "quiet luxury, editorial"
design-system/          # HTML/CSS mirror of the UI, synced to a Claude Design project
supabase/               # Backend-as-code (Edge Functions + auth email templates) — NOT in the Xcode build
├── templates/          # Branded auth emails (confirm-signup + change-email)
└── functions/          # create-payment-intent, stripe-webhook, delete-account (+ README)

SoulfullGatherings/
├── SoulfullGatheringsApp.swift   # @main; injects env, forces dark mode, routes soulfull:// deep links
├── App/                          # AppState, AuthManager, AppSettings, RootView, MainTabView, BottomNav
├── Core/
│   ├── Models/Models.swift       # All domain models + mock data
│   ├── DesignSystem/             # Theme, Components, SoulGlass, Pressable, shaders (Shaders.metal/ShaderFX), etc.
│   ├── Services/                 # SupabaseConfig/Service, PaymentService, AppError
│   └── Utils/                    # Haptics, ArtworkTones
└── Features/                     # One folder per feature: Auth, Welcome, Onboarding, Home,
                                  # Retreats, Practice, Circle, Profile
```

See the **File Map** in `CLAUDE.md` for a line-by-line description of every file.

## Architecture notes

- **MVVM with Observation.** Each stateful screen has a paired `@Observable @MainActor final class …ViewModel`. App-level singletons (`AppState`, `AppSettings`, `AuthManager`) are also `@Observable @MainActor`, injected from `@main` and read with `@Environment(Type.self)`.
- **Three-tier navigation.** `AppState.stage` (`loading → welcome → onboarding → main`) drives `RootView`; `MainTabView` hosts four tabs via a custom glass `BottomNav`; Home and Practice each own a private `NavigationStack` with a typed `Route` enum.
- **Persistence is `AppSettings`,** a `UserDefaults` wrapper with `didSet` writes (keys prefixed `sg.`) — *not* `@AppStorage`.
- **Design system is centralized.** All brand values live in `Theme.swift`; glass goes through `SoulGlass`, touch physics through `Pressable`, shaders through `ShaderFX` wrappers. Never hardcode colors/fonts or branch on OS in feature code.
- **Haptics are mandatory** on every interactive tap (`Haptics.tap/bump/select/success/prepare`).

There are rendering gotchas that have actually bitten this codebase (Metal effects over UIKit-backed views, `visualEffect` escaping clips, `scaledToFill` inflating layout) — read the **Rendering gotchas** section of `CLAUDE.md` before adding effects.

## Backend (Supabase + Stripe)

- **Migrations were removed from the repo on 2026-09-07**, after all nine had been applied to the live project (`supabase migration list --linked` showed local and remote in step through 0009). The live database is now the only description of the schema; recover the SQL with `git show d20e3f6:supabase/migrations/`. A new migration goes in `supabase/migrations/` and is applied with `supabase db push`. Content tables: `retreats`, `programs`, `practice_sessions`; user tables: `profiles`, `bookings` (all RLS-protected). See the **Backend** section of `CLAUDE.md` for the column map and the RLS-role gotcha (anonymous guests authenticate as `authenticated`, not `anon` — public tables must grant SELECT to both).
- **Required Supabase Auth settings:** Anonymous sign-ins **ON**, and if "Confirm email" is on, allow-list the redirect URL `soulfull://auth-callback` (Authentication → URL Configuration → Redirect URLs).
- **Payments** flow through two Edge Functions (`create-payment-intent`, `stripe-webhook`) plus `delete-account` for App Store account-deletion compliance. The client never holds Stripe secrets — even the publishable key is returned by the function. Deploy steps and the required restricted-key permissions are in [`supabase/functions/README.md`](supabase/functions/README.md).

## Design ↔ code sync

`design-system/` is an HTML/CSS mirror of the app's UI, pushed to a **Claude Design** project where the UX team edits visually. When you change design-relevant code (tokens, shared components, or a screen's layout/copy), update the matching `design-system/` file in the same commit. Publishing to Claude Design is deliberate (`/sync-design push` — incremental, never wholesale). The full token/component map and round-trip rules are in [`design-system/README.md`](design-system/README.md).

## Tests

There are no tests at the moment. The `SoulfullUITests` UI-test target was removed from `project.yml` (target, scheme, and test files all gone), and there are no unit tests yet.

The app still honors the test launch hooks `-uitest-reset` and `-uitest-onboarded` (handled in `SoulfullGatheringsApp.swift`), so re-adding a UI-test target later is straightforward. Prior UI tests drove the welcome → onboarding → home → retreat-detail → practice flow and attached named screenshots reviewed with `xcrun xcresulttool export attachments`.

## Current state

- **Done:** anonymous auth + email/password accounts (create / sign-in / sign-out / delete), email-confirmation deep linking, profile sync; Welcome; Onboarding; Home; Retreats stack + editorial detail; full Practice tab; Stripe reservations (deployed + verified in test mode).
- **Mock-driven:** `programs` and `CommunityCircle` on Home (`fetchPrograms()` exists but is unused); all Journal / Exercise / Recipe / Massage content (pending their own tables); journal reflections are device-local only.
- **Placeholder:** Circle (Community) tab.
- **Not yet built:** Sign in with Apple, a bookings history UI, refund handling, and membership subscriptions (which must use StoreKit IAP, not Stripe).

> **Backend status:** the Supabase project (`qkepgohdosmzebdmsctn.supabase.co`, "Soulfull iOS") is live (`ACTIVE_HEALTHY`) — the earlier paused/NXDOMAIN outage is resolved. Only `retreats`, `profiles`, and `bookings` tables exist so far, and `retreats` is currently empty, so Home/stack still render mock content until it's seeded.
