# Soulfull Gatherings — iOS (SwiftUI)

A native iOS app for a wellness retreat and community platform — dark, editorial, "quiet luxury" aesthetic throughout. Built with **SwiftUI**, **iOS 18+**, **Swift 6**, and an **MVVM + Observation** architecture. Backed by **Supabase** (PostgreSQL + Storage + Auth). Stripe powers retreat reservations server-side, but the client payment rail is **removed from v1**.

> **`CLAUDE.md` is the deep architecture reference** — the full file map, backend schema, RLS gotchas, and conventions live there. This README is the get-it-building onboarding guide. For the design direction see [`docs/DESIGN.md`](docs/DESIGN.md); for backend deploy steps see [`supabase/functions/README.md`](supabase/functions/README.md); for the Claude Design mirror see [`design-system/README.md`](design-system/README.md).

## What's inside

- **Welcome** — splash (breathing logo) → 3 explainer slides → onboarding
- **Onboarding** — name → intention → nervous-system check-in → cadence → finish (4 questions + a closing slide)
- **Home** — dashboard: greeting (+ a streak line once it reaches two days), mood chips, a **Continue** card for the most recently unfinished practice, ritual card, retreat glimpse, and a Digital Retreats shelf that hides itself until `programs` has rows
- **Retreats** — viewport-aligned stacked name picker over crossfading photo backdrops → full editorial detail spread with a "Request a place" CTA (opens a support email). The long-form brochure comes from the `retreats.experience` jsonb column, and photos from Supabase Storage, so **adding a retreat is a row and an upload — no app release**. See [`docs/ADDING-A-RETREAT.md`](docs/ADDING-A-RETREAT.md).
- **Practice** — media categories (Somatic / Breathwork / Meditation) → session list → AVKit player, plus Journal prompts, Exercises, Recipes, and Personal Massages
- **You** — real account UI (create / sign in / sign out / delete account), onboarding status, and a Privacy · Terms · Retreat policy · Support row
- **Auth** — an anonymous Supabase guest session opens on launch and upgrades **in place** to a permanent account. **Browsing never requires an account**; the sheet is raised just-in-time at the first practice and replays the tap you were making (`AccountGate`). **Sign in with Apple** is the only third-party provider, alongside email/password with three email-confirmation paths (deep link, emailed code, confirmed-elsewhere poll).
- **Practice history** — every practice opened is recorded server-side to `practice_plays`; it drives resume points, completion seals, the Home Continue card and streak, and the content-creator payout report
- **Payments** — the **server** rail (two Edge Functions) is built and verified in Stripe test mode, but the **client** rail is gone from v1: the `StripePaymentSheet` dependency, `PaymentService` and `RetreatCheckoutView` were deleted, because the SDK linked a card scanner that forced a camera permission for a feature the app can't reach. The CTA is "Request a place". See [v1 ships narrower](#v1-ships-narrower-than-the-codebase).

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
| Payments | Stripe via Supabase Edge Functions (server-side only — no payment SDK in the app) |
| Fonts | Geist (six weights, registered in `Info.plist`) — no serif/SF split, everything is Geist |
| Tests | One UI-test target — `SoulfullUITests/AccountGateTests.swift` (2 tests) covering the account gate. No unit tests yet. |

## Prerequisites

- **Xcode 16+** with the iOS 18 SDK. The **Metal toolchain** is a separate Xcode component and the shaders won't build without it — `xcodebuild -downloadComponent MetalToolchain` if you hit "cannot execute tool 'metal'".
- **XcodeGen** — `brew install xcodegen`
- A **Supabase** project. The app needs one to do anything real: auth, the retreat catalog and all practice content come from it. **Nothing falls back to sample data** — an unreachable backend renders an explicit offline/error state, and an unseeded `practice_sessions` renders "Coming soon", rather than either serving mock content as if it were real. For payments (off in v1), a **Stripe** account.

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

> **If Stripe ever comes back:** resolve it from **`github.com/stripe/stripe-ios-spm`** (the slim, SPM-optimized distribution), *not* `stripe/stripe-ios` — the main repo's multi-GB history makes resolution extremely slow. It is **not** a dependency today.

## Project layout

```
Config/                 # Secrets.xcconfig (gitignored) + .example template
Resources/Fonts/        # Geist .otf files (added as a resources build phase)
docs/                   # DESIGN.md (direction), APP-STORE-READINESS.html (submission audit),
                        # APP-REVIEW-NOTES.md (the text to paste into App Store Connect), PLAN-*.md (parked work)
design-system/          # HTML/CSS mirror of the UI, synced to a Claude Design project
supabase/               # Backend-as-code (Edge Functions + auth email templates) — NOT in the Xcode build
├── templates/          # Branded auth emails (confirm-signup + change-email)
└── functions/          # create-payment-intent, stripe-webhook, delete-account (+ README)
SoulfullUITests/        # AccountGateTests.swift — drives the account gate end to end

SoulfullGatherings/
├── SoulfullGatheringsApp.swift   # @main; injects env, forces dark mode, routes soulfull:// deep links
├── PrivacyInfo.xcprivacy         # Privacy manifest (UserDefaults required-reason + collected-data types)
├── App/                          # AppState, AuthManager, AppSettings, RootView, MainTabView,
│                                 # BottomNav, ConnectionBanner
├── Core/
│   ├── Models/Models.swift       # All domain models + mock data
│   ├── DesignSystem/             # Theme, Components, SoulGlass, Pressable, shaders (Shaders.metal/ShaderFX), etc.
│   ├── Services/                 # SupabaseConfig/Service, PracticeProgressStore,
│   │                             # LocalUserStore, AppFeatures (v1 flags), LegalLinks, AppError
│   └── Utils/                    # Log (os.Logger — no print() anywhere), Haptics, ArtworkTones
└── Features/                     # One folder per feature: Auth (gate + account sheet + Apple button),
                                  # Welcome, Onboarding, Home, Retreats (+ PostPurchase/ — the reserved-retreat
                                  # experience), Practice, Circle (parked), Profile
```

See the **File Map** in `CLAUDE.md` for a line-by-line description of every file.

## Architecture notes

- **MVVM with Observation.** Each stateful screen has a paired `@Observable @MainActor final class …ViewModel`. App-level singletons (`AppState`, `AppSettings`, `AuthManager`) are also `@Observable @MainActor`, injected from `@main` and read with `@Environment(Type.self)`.
- **Three-tier navigation.** `AppState.stage` (`loading → welcome → onboarding → main`) drives `RootView`; `MainTabView` hosts three tabs (Home / Practice / You) via a custom glass `BottomNav`, which builds itself from `MainTab.allCases`; Home and Practice each own a private `NavigationStack` with a typed `Route` enum.
- **Persistence is `AppSettings`,** a `UserDefaults` wrapper with `didSet` writes (keys prefixed `sg.`) — *not* `@AppStorage`.
- **Design system is centralized.** All brand values live in `Theme.swift`; glass goes through `SoulGlass`, touch physics through `Pressable`, shaders through `ShaderFX` wrappers. Never hardcode colors/fonts or branch on OS in feature code.
- **Haptics are mandatory** on every interactive tap (`Haptics.tap/bump/select/success/prepare`).

There are rendering gotchas that have actually bitten this codebase (Metal effects over UIKit-backed views, `visualEffect` escaping clips, `scaledToFill` inflating layout) — read the **Rendering gotchas** section of `CLAUDE.md` before adding effects.

## Backend (Supabase + Stripe)

- **Migrations were removed from the repo on 2026-09-07**, after all nine had been applied to the live project (`supabase migration list --linked` showed local and remote in step through 0009). The live database is now the only description of the schema; recover the SQL with `git show d20e3f6:supabase/migrations/`. A new migration goes in `supabase/migrations/` and is applied with `supabase db push`. Content tables: `retreats`, `programs`, `practice_sessions`; user tables: `profiles`, `bookings` (all RLS-protected). See the **Backend** section of `CLAUDE.md` for the column map and the RLS-role gotcha (anonymous guests authenticate as `authenticated`, not `anon` — public tables must grant SELECT to both).
- **Required Supabase Auth dashboard settings** — the app silently breaks without them: (1) **Anonymous sign-ins ON** (the app boots a guest session and upgrades it in place). (2) If **Confirm email** is on, allow-list the redirect URL `soulfull://auth-callback` under Authentication → URL Configuration → Redirect URLs. (3) **Custom SMTP** — the built-in sender is `Supabase Auth <noreply@mail.app.supabase.io>`, not editable on any plan, and rate-limited to a handful of emails per hour project-wide. (4) **Apple provider ON** with bundle ID `com.soulfullgatherings.app` in *Client IDs* and *Secret Key* left **blank** — the native token flow verifies the token's `aud` against that list, so a filled secret rejects every Apple sign-in. **That is the primary way into an account; verify it before shipping.**
- **Payments** (off in v1, see above) flow through two Edge Functions (`create-payment-intent`, `stripe-webhook`) plus `delete-account` for App Store account-deletion compliance. Double-charge and overselling are blocked server-side in `create-payment-intent`, where they belong. The client never holds Stripe secrets — even the publishable key is returned by the function. Deploy steps and the required restricted-key permissions are in [`supabase/functions/README.md`](supabase/functions/README.md).

## Design ↔ code sync

`design-system/` is an HTML/CSS mirror of the app's UI, pushed to a **Claude Design** project where the UX team edits visually. When you change design-relevant code (tokens, shared components, or a screen's layout/copy), update the matching `design-system/` file in the same commit. Publishing to Claude Design is deliberate (`/sync-design push` — incremental, never wholesale). The full token/component map and round-trip rules are in [`design-system/README.md`](design-system/README.md).

## Tests

One UI-test target: `SoulfullUITests/AccountGateTests.swift`, two tests driving the account gate end to end. It is scoped `SoulfullUITests: [test]` in the scheme, so archives don't build it. No unit tests yet.

```bash
xcodebuild test -project SoulfullGatherings.xcodeproj -scheme SoulfullGatherings \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath build/x.xcresult -only-testing:SoulfullUITests
```

Screenshots come out with `xcrun xcresulttool export attachments --path build/x.xcresult --output-path build/attach` (map names through `manifest.json`).

**Reach for this whenever a control "doesn't work".** The accessibility dump (`app.debugDescription`) reports real hit frames — which is how a button that looked 38pt but hit-tested at 11pt was found, a bug invisible to inspection and to two rounds of reasoning. The `-uitest-reset` / `-uitest-onboarded` / `-tab <name>` launch hooks are what make the run deterministic.

## v1 ships narrower than the codebase

Three flags in `Core/Services/AppFeatures.swift` gate what a user can reach. **Nothing was deleted** — restoring a feature is flipping its flag plus the follow-up work its doc comment lists.

| Flag | v1 | Why |
|---|---|---|
| `paymentsEnabled` | `false` | The **server** rail is built and test-verified; the **client** rail is deleted (the SDK forced a camera permission for an unreachable feature). Shipping payments needs that restored from git history, plus live keys, a demo account with a seeded `paid` booking (a reviewer can't complete a charge), and curated `PostBooking` content for **every** reservable retreat — which only Mallorca has. The retreat CTA is **"Request a place"** (a support email). The flag's doc comment carries the full checklist. |
| `depositInstallmentsEnabled` | `false` | Deposit + monthly installments are **copy only** — the server charges the full price in one payment. The copy had reached the pay button: checkout rendered a hardcoded `"€800"` while the function charged ~$5,678. **Never put brochure copy on a pay button.** |
| `circleTabEnabled` | `false` | The tab's whole content was "lands here next" — App Store Guideline 4.2. `MainTab` omits the case and `BottomNav` builds from `allCases`, so it disappears on its own. |

Practice media is **data-gated, not code-gated**: `PracticeView` asks which of Somatic / Breathwork / Meditation have rows and dims the rest to "Coming soon". Seeding `practice_sessions` lights them up with no app release. The distinction between "the table is empty" and "we're offline" is deliberate — collapsing them told a user on a train that the content doesn't exist.

For the full submission audit see [`docs/APP-STORE-READINESS.html`](docs/APP-STORE-READINESS.html); for the App Store Connect review text see [`docs/APP-REVIEW-NOTES.md`](docs/APP-REVIEW-NOTES.md).

## Current state

- **Done:** anonymous auth upgradable in place; just-in-time account gating (`AccountGate`) with **Sign in with Apple** + email/password; email confirmation via three paths (deep link / emailed code / confirmed-elsewhere poll); account deletion (App Store 5.1.1(v)); `profiles` sync; Welcome; Onboarding; Home; Retreats stack + editorial detail; full Practice tab; **server-side practice history** driving resume, streaks and the creator-payout report.
- **Built but off in v1:** Stripe reservations — the **server** half is deployed and verified in test mode; the client half is deleted (recover from git history). The Mallorca post-purchase experience — welcome hub, to-do's, packing, 1:1 guide booking — is intact but unreachable.
- **Deliberately not built: any AI.** No companion, assistant or chat, and none planned. A mocked concierge and a "Soul AI" welcome slide were removed on 2026-09-11.
- **Mock-driven:** `CommunityCircle` on Home; all Journal / Exercise / Recipe / Massage *content* (pending their own tables). Their **progress** is real and server-backed even though the content isn't. Journal reflections stay on the device — file-backed under Application Support with `NSFileProtectionComplete` and excluded from backups, not in `UserDefaults`.
- **Parked:** Circle (Community) tab.
- **Content is data:** retreats (row + brochure jsonb + Storage photo) need no release. Practice *sessions* are a table too, but the written libraries — journal prompts, exercises, recipes, massages — are still hardcoded in `Models.swift`.
- **Not yet built:** a bookings history UI (the data exists), refund handling, and membership subscriptions (which must use StoreKit IAP, not Stripe). Google sign-in was built and deliberately removed — Apple is the only third-party provider.

> **Backend status** — Supabase project `qkepgohdosmzebdmsctn.supabase.co` ("Soulfull iOS"), `ACTIVE_HEALTHY`. Verified 2026-09-07:
>
> | Table | State |
> |---|---|
> | `retreats` | 7 rows, **4 upcoming** — Lapland (2027-01-10), Chamonix (2027-02-02), Mallorca (2027-07-21), Dolomites (2027-09-08). Kyoto / Sedona / Bali are past and correctly hidden by the `start_date > today` filter. Every `group_chat_url` is still `null`. |
> | `programs` | Exists, **0 rows** — Home's Digital Retreats shelf hides itself. |
> | `practice_sessions` | Exists, **0 rows** — all three media tracks read "Coming soon". Seeding needs no app release. |
> | `profiles` / `bookings` / `practice_plays` | Exist, RLS-protected. Row counts aren't observable with the anon key — RLS filters them to the caller, so an empty result here proves nothing about what's in them. |
>
> Probe it read-only with the anon key from `Config/Secrets.xcconfig`. **A 200 with `[]` means the table exists and is unseeded; only a 404 means it's missing** — conflating the two sends you to write a migration when the actual job is seeding.
