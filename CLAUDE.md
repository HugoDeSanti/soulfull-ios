# Soulfull Gatherings — iOS App

SwiftUI iOS app for a wellness retreat and community platform. Dark, editorial aesthetic throughout. Backend is Supabase (PostgreSQL + Storage + Auth — anonymous guest sessions that can be upgraded into permanent email/password accounts). Mock data still exists in `Models.swift` and is used while real Supabase tables are being seeded.

**Minimum deployment target: iOS 18.** Always use the latest Swift and SwiftUI idioms — `@Observable` over `ObservableObject`, `@Environment` over `@EnvironmentObject`, `@State` over `@StateObject`/`@ObservedObject`, typed throws, `NavigationStack` with typed `Route` enums, etc. Do not reach for deprecated patterns for compatibility — there is no older OS to support. Swift language version is pinned to 6.0 in `project.yml`.

## Build & Run

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` from `project.yml`. `project.yml` is the single source of truth for the build (target, Swift 6, iOS 18 deployment, bundle ID `com.soulfullgatherings.app`, Supabase SPM dependency, Geist font resources, `Secrets.xcconfig` injection). Regenerate `.xcodeproj` whenever you edit `project.yml`.

```bash
# Regenerate the Xcode project after editing project.yml
xcodegen generate

# Open in Xcode
open SoulfullGatherings.xcodeproj
```

Build and run via Xcode (⌘R). Target: iPhone, iOS 18+. Portrait only. Dark mode is forced at the `WindowGroup` level via `.preferredColorScheme(.dark)`.

## Architecture

**Pattern:** MVVM with SwiftUI. Each screen that needs state has a paired `ViewModel` declared `@Observable @MainActor final class …` (the Observation framework, not `ObservableObject`/`@Published`). App-level singletons — `AppState`, `AppSettings`, `AuthManager` — are also `@Observable @MainActor` and are injected into the SwiftUI environment from `@main` and read with `@Environment(Type.self)`.

**Three-tier navigation:**
1. **Stage level** — `AppState.stage` (`Stage` enum: `loading → welcome → onboarding → main`) drives the top-level switch in `RootView`. Transitions are animated (`withAnimation(.easeInOut(…))`) and the onboarded flag is persisted in `UserDefaults` (`sg.hasOnboarded`) via `AppSettings`.
2. **Tab level** — `App/MainTabView.swift` hosts four tabs (`MainTab`: `home`, `practice`, `circle`, `you`) with the custom `BottomNav` glass bar. The Home and Practice tabs each wrap their content in a private per-tab `NavigationStack` root (`HomeRoot`, `PracticeRoot`); the Circle and You tabs render placeholders directly with no stack.
3. **Item level** — each tab root holds a typed `Route` enum and a `@State private var path: [Route]`. `HomeRoot.Route` covers `retreatsStack`/`retreatDetail`; `PracticeRoot.Route` covers the practice session list plus journal/exercise/recipe/massage list and detail destinations. Native swipe-back works because navigation is value-based.

**Auth:** `AppState.initializeAuth()` runs from the app entry `.task`; it calls `AuthManager.initialize()` and then routes to the correct stage. `AuthManager` establishes (or restores) an **anonymous** Supabase session on launch, then lets the user **upgrade that guest into a permanent email/password account** in place (`createAccount` calls `auth.update` on the anonymous user so the same `id` and any data carry over; a non-anonymous user falls through to `signUp`). Also exposes `signIn`, `signOut` (signs out then re-opens a fresh anonymous session so the app keeps working). Liveness is `AuthManager.State` (`initializing`, `authenticated`, `failed(String)`); identity is `isAnonymous`, `hasAccount` (= authenticated **and** not anonymous — gate paid/Reserve flows on this, not `isAuthenticated`), `email`, and `userID`. **Sign in with Apple is not wired yet** (needs the Apple capability + entitlement) — Phase 1 ships email/password only.

## File Map

```
Config/
├── Secrets.xcconfig                   # Gitignored — real Supabase host + anon key (never commit)
└── Secrets.xcconfig.example           # Template; copy to Secrets.xcconfig on a new machine

supabase/
└── migrations/
    └── 0001_profiles.sql              # `profiles` table + RLS + auto-create/updated_at triggers (run in dashboard SQL editor or `supabase db push`). NOT part of the Xcode build.

SoulfullGatherings/
├── SoulfullGatheringsApp.swift        # @main entry; creates AppState, injects environment, forces dark mode, kicks off auth via .task
├── Info.plist                         # Bundle metadata; SupabaseHost/SupabaseAnonKey resolve from xcconfig; UIAppFonts (Geist); portrait-only
├── Assets.xcassets                    # Asset catalog: images + AppIcon (Image(_:) resolves names here)
│
├── App/                               # App-level: global state, routing, auth, navigation shell
│   ├── AppState.swift                 # @Observable stage router (loading/welcome/onboarding/main) + lifecycle; initializeAuth()/resetAll()
│   ├── AuthManager.swift              # @Observable Supabase auth; initialize() restores/opens anonymous session; createAccount (upgrades guest in place)/signIn/signOut; exposes isAnonymous/hasAccount/email/userID
│   ├── AppSettings.swift              # @Observable UserDefaults wrapper (didSet persistence); hasOnboarded/userName/bodyState/frequency/intentions
│   ├── RootView.swift                 # Stage switcher with opacity + motion transitions
│   ├── MainTabView.swift              # Four-tab container + private HomeRoot/PracticeRoot NavigationStacks
│   └── BottomNav.swift                # Custom floating glass tab bar (@Binding current tab)
│
├── Core/                              # Shared foundational code
│   ├── Models/
│   │   └── Models.swift               # All domain models + mock data (Profile, Retreat, Program, CommunityCircle, PracticeCategory, MediaKind, MediaItem, PracticeSession, PracticeMenuItem, JournalPrompt, ExerciseStep, Exercise, Recipe, Massage, IntentionOption, BodyStateOption, FrequencyOption, MoodChip)
│   ├── DesignSystem/
│   │   ├── Theme.swift                # Brand colors, gradients, Geist typography helpers, shape constants + Color(hex:)
│   │   └── Components.swift           # SGPrimaryButton, GlassCard, SectionLabel, PhotoBackdrop, CircleIconButton, TabPlaceholder, PulseModifier
│   ├── Services/
│   │   ├── SupabaseConfig.swift       # Loads + validates Supabase host/anon key from Info.plist (Bundle.main); ConfigError (missingKey/malformedHost)
│   │   ├── SupabaseService.swift      # Actor data layer: nonisolated client, 5-min TTL caches, fetchRetreats/Programs/PracticeSessions, fetchProfile/upsertProfile (uncached), signedMediaURL, invalidateCache
│   │   └── AppError.swift             # App-level LocalizedError enum (configurationMissing/authFailure/networkFailure/unknown)
│   └── Utils/
│       └── Haptics.swift              # @MainActor UIKit haptic facade with cached generators (tap/bump/select/success/prepare)
│
└── Features/                          # One folder per feature/tab; each owns its views + VMs
    ├── Auth/
    │   ├── AccountView.swift          # Create-account / sign-in sheet (glass form: name/email/password); presented from the You tab
    │   └── AccountViewModel.swift     # @Observable; form state + validation; calls AuthManager then syncs profile (push local answers on create / hydrate settings on sign-in)
    ├── Welcome/
    │   └── WelcomeView.swift          # Splash (logo breathing) + 3 explainer slides → routes to onboarding
    ├── Onboarding/
    │   ├── OnboardingView.swift       # 4-question flow (name/intention/state/frequency) + finish screen; step sub-views inline
    │   └── OnboardingViewModel.swift  # Step state machine, per-step validation (canAdvance), next/back, commit to AppSettings
    ├── Home/
    │   ├── HomeView.swift             # Dashboard: greeting, mood chips, ritual card, programs, circles, retreat glimpse → opens Retreats
    │   └── HomeViewModel.swift        # Greeting from hour, mood selection, loads retreats from Supabase (mock programs/circles)
    ├── Retreats/
    │   ├── RetreatsStackView.swift    # Viewport-aligned scrolling name stack with crossfading photo backdrop; loadError retry
    │   ├── RetreatsViewModel.swift    # Retreat array + active index, loading/error state, fetches from Supabase
    │   └── RetreatDetailView.swift    # Editorial full-bleed detail + Reserve button (local @State only)
    ├── Practice/
    │   ├── PracticeView.swift         # Landing: scrolling cards for media categories (Somatic/Breathwork/Meditation) + menu items; onSelect callback
    │   ├── PracticeShared.swift       # Shared chrome: PracticeBackBar, PracticeListScaffold, NumberedStepRow
    │   ├── PracticeListView.swift     # Audio/video sessions for one PracticeCategory (Supabase via PracticeViewModel) → player sheet
    │   ├── PracticeViewModel.swift    # @Observable; loads sessions per category, falls back to PracticeSession.mock(for:)
    │   ├── PracticePlayerView.swift   # Resolves MediaItem URL (signed Storage or direct http) and plays via AVKit; reused by sessions + massages
    │   ├── JournalView.swift          # JournalListView + JournalDetailView (prompt + device-local TextEditor reflection)
    │   ├── ExerciseView.swift         # ExerciseListView + ExerciseDetailView (numbered steps)
    │   ├── RecipeView.swift           # RecipeListView + RecipeDetailView (full-bleed hero, meta pills, ingredients, method)
    │   └── MassageView.swift          # MassageListView + MassageDetailView (guided media via player sheet + technique steps)
    ├── Circle/
    │   └── CommunityPlaceholder.swift # Branded empty state for Circle tab (delegates to TabPlaceholder)
    └── Profile/
        └── ProfilePlaceholder.swift   # You tab: greeting + intentions + account status; Create account/Sign in (→ AccountView sheet) when guest, Sign out when signed in; dev-only "Reset onboarding" gated behind #if DEBUG; custom layout, not TabPlaceholder
```

> Resources (`Resources/Images/`, `Resources/Fonts/`) live at the **repo root**, not under `SoulfullGatherings/`. `project.yml` adds `Resources/Fonts` as a resources build phase; images are managed through `SoulfullGatherings/Assets.xcassets`.

## Design System

All brand values live in `Theme.swift` (a static-only `enum` namespace). Use `Theme.*` constants — never hardcode colors or font sizes. Colors are pre-converted from oklch design tokens to sRGB by hand; if tokens change they must be manually recalculated here.

| Token | Usage |
|---|---|
| `Theme.bg` / `Theme.bgDeep` | Near-black canvas (faint olive tint) |
| `Theme.surface` | Card fills |
| `Theme.ink` | Warm cream — primary text |
| `Theme.inkSoft` | Muted cream — secondary text |
| `Theme.muted` | Tertiary / metadata text |
| `Theme.accent` / `Theme.accentSoft` | Olive-green brand accent |
| `Theme.honey` | Amber glow for selected states |
| `Theme.line` / `Theme.glassBorder` / `Theme.glassBorderHigh` | Hairline / glass strokes |
| `Theme.headline(_:weight:)` | Headline font (Geist at requested weight) |
| `Theme.body(_:weight:)` | Body / UI font (Geist at requested weight) |
| `Theme.eyebrow(_:)` | Small tracked caps (Geist Regular) |

- **Typography:** Geist family ships Thin/Light/Regular/Medium/SemiBold/Bold (registered in `Info.plist` `UIAppFonts`); heavier weights fall back to Bold, lighter to Regular. There is **no serif/SF Pro split — everything is Geist.** Headlines use negative `kerning` (e.g. `-0.2`/`-0.3`); body/eyebrow use positive `tracking` (2–3). `Text.sgEyebrow()` applies font + tracking + uppercase + color in one call.
- **Glass surfaces:** `.ultraThinMaterial` + a `Theme.glassBorder` `strokeBorder`. `GlassCard` wraps this; `CircleIconButton` is the smaller glass chrome button. `SGPrimaryButton` is a ghost/fill pill using a `DragGesture(minimumDistance: 0)` for immediate press feedback.
- **Photo backdrops:** `PhotoBackdrop(imageName:blur:darken:)` — solid `Theme.bg` floor, blurred/saturated image, vignette. Reused everywhere; `blur` and `darken` vary per screen.
- **Shape constants:** `Theme.cardRadius` (22), `Theme.pillRadius` (999 / Capsule).
- `PulseModifier` animates forever (`autoreverses`) — use only for persistent live indicators.

## Backend

**Supabase** hosts content data (PostgreSQL), media (Storage), and the user session (Auth — anonymous guests upgradable to email/password accounts). The Swift SDK (`import Supabase`, `@preconcurrency`) is added via SPM.

**Migrations** live in `supabase/migrations/` at the repo root (run them in the dashboard SQL editor or via `supabase db push`). They are **not** part of the Xcode build — `project.yml` only sources `SoulfullGatherings/` and `Resources/Fonts`, so adding SQL needs no `xcodegen generate`.

**`SupabaseService` is an actor singleton.** It exposes `client` `nonisolated` (so `AuthManager` can reach the `SupabaseClient` without an actor hop) and maintains three independent in-memory caches (retreats, programs, practice sessions) each with a 5-minute TTL. There is no automatic invalidation — call `invalidateCache()` on logout/explicit refresh. Bootstrap is fatal: if `SupabaseConfig.make()` throws (missing/placeholder credentials) the app crashes at startup with setup instructions.

**Credentials flow:** `Config/Secrets.xcconfig` → build settings → `Info.plist` (`SupabaseHost`, `SupabaseAnonKey` via `$(SUPABASE_HOST)` / `$(SUPABASE_ANON_KEY)`) → `Bundle.main` → `SupabaseConfig` → `SupabaseService`. Never hardcode credentials in Swift source.

- `Config/Secrets.xcconfig` is gitignored and contains the real anon key. Copy `Secrets.xcconfig.example` to set up a new machine.
- `SUPABASE_HOST` stores the host only (e.g. `abc123.supabase.co`) — no `https://` prefix because `//` is a comment delimiter in xcconfig. `SupabaseConfig` rejects empty values and anything starting with `YOUR_`, and validates the host builds a usable `https://` URL.

**Database tables** (snake_case columns, mapped by private `…Row` DTO `CodingKeys` in `SupabaseService.swift`; each Row has a computed property returning the domain model):

| Table | Key columns | Fetch | Limit |
|---|---|---|---|
| `retreats` | `id`, `name`, `country`, `start_date`, `end_date`, `max_guests`, `price_usd`, `tags` (array), `blurb`, `image_url`, `tone_top`, `tone_mid`, `tone_base` | `fetchRetreats()` (order by `start_date`) | 50 |
| `programs` | `id`, `title`, `lead`, `date_range`, `days`, `image_url` | `fetchPrograms()` (order by `title`) | 50 |
| `practice_sessions` | `id`, `category` (`somatic`/`breathwork`/`meditation`), `title`, `lead`, `media_kind` (`audio`/`video`), `storage_path`, `duration_seconds`, `image_url`, `blurb` | `fetchPracticeSessions(category:)` (filtered by `category`) | 100 |
| `profiles` | `id` (uuid = `auth.users.id`), `email`, `full_name`, `intentions` (text[]), `body_state`, `frequency`, `stripe_customer_id` (Phase 2, server-only), `created_at`, `updated_at` | `fetchProfile(id:)` / `upsertProfile(_:)` (uncached) | 1 |

- `RetreatRow` parses `start_date`/`end_date` with a per-call `DateFormatter` (`yyyy-MM-dd`, `en_US_POSIX`); `Retreat` then derives its display `when` string and `durationDays`/`priceFormatted` itself.
- **Tone colors** are hex strings (e.g. `#728FA5`) decoded via `Color(hex:)` (extension in `Theme.swift`).
- `CommunityCircle` has **no** Supabase fetch yet — it is mock-only (`CommunityCircle.mock`). `programs` has a `fetchPrograms()` method but is **not** yet called by any ViewModel (Home uses `Program.mock`).
- **`profiles` is protected by row-level security** (`auth.uid() = id` for select/insert/update; no delete; no client write to `stripe_customer_id`). A row is auto-created by an `auth.users` insert trigger (covers anonymous guests too), and `updated_at` is bumped by a trigger. The app only ever reads/writes its **own** row. `upsertProfile` deliberately omits `stripe_customer_id` and timestamps so it never clobbers server-managed columns. Account creation pushes local onboarding answers up; sign-in hydrates `AppSettings` from the row. **Caveat:** keep "Confirm email" **off** during development so the anonymous→permanent upgrade completes immediately; enabling it requires handling the email-confirmation redirect.

**Practice media** lives in a Supabase **Storage** bucket (default `practice-media`); `practice_sessions.storage_path` stores only the bucket-relative path. `SupabaseService.signedMediaURL(path:bucket:expiresIn:)` (default 1-hour expiry) turns a private path into a time-limited signed URL. `PracticePlayerView` plays a `storagePath` that is an absolute `http(s)` URL directly (without signing) and signs everything else; the mock sessions use absolute sample URLs.

**Adding a new fetch:** add a private `Codable` `…Row` DTO inside `SupabaseService.swift` with `CodingKeys` mapping snake_case → camelCase and a computed property returning the app model. Then add a `func fetch…() async throws -> [T]` (consider a cache + TTL if it mirrors the existing pattern). Wrap/surface failures through `AppError`.

## Key Conventions

- `@Observable @MainActor` on all ViewModels and app-level singletons (`AppState`, `AppSettings`, `AuthManager`). No `ObservableObject`/`@Published`.
- Haptics are mandatory on every interactive tap: `Haptics.tap()` for secondary, `Haptics.bump()` for primary CTAs, `Haptics.select()` for scroll/toggle updates, `Haptics.success()` for confirmations; `Haptics.prepare()` to warm the engine on gesture start.
- Navigation is value-based (`NavigationStack` + typed `Route` enums per tab root), not `NavigationLink` with destinations.
- All onboarding answers are validated before `canAdvance` returns `true`; never allow advancing with empty state. The step machine has 5 cases but `questionCount = 4` (the `finish` case is not a question).
- Mock data is defined as static `.mock` / `.mock(for:)` / `.all` properties on model types in `Models.swift`.
- **Persisted user settings live in `AppSettings`, not `@AppStorage`** — properties are backed by `UserDefaults` with `didSet` writes. All keys are prefixed `sg.` (`sg.hasOnboarded`, `sg.userName`, `sg.bodyState`, `sg.frequency`, `sg.intentions`).
- `AppSettings.intentions` is exposed as a `Set<String>` but serialized to a comma-joined string (`intentionsRaw`) — always read/write the `Set` property, never `intentionsRaw` (which is `private`).
- Domain models are value types conforming to `Identifiable` + `Hashable` (keyed on `id`) for `NavigationStack` use. Durations are stored in seconds (`durationSeconds`) with a `.durationLabel` computed property.
- **Gate paid / account-only flows on `auth.hasAccount`, never `auth.isAuthenticated`** — the latter is true for anonymous guests. Read/write money or entitlement state server-side only (RLS for reads; webhooks via service role for writes); never trust the client.

## Current State

- **Implemented:** anonymous Supabase auth on launch; **email/password accounts (Phase 1)** — create-account upgrades the anonymous guest in place, sign-in/sign-out, `profiles` table with RLS + sync (You tab → `AccountView`); Welcome flow; Onboarding (4 questions + finish); Home dashboard; Retreats stack + detail; full Practice tab (category/menu landing → list → detail/player for the 3 media tracks plus Journal Prompts, Exercises, Food Recipes, Personal Massages; media plays via `PracticePlayerView`).
- **Backend wiring:** `SupabaseService` (actor + caching) is live. `retreats` is fetched from Supabase by both `HomeViewModel` and `RetreatsViewModel`. `practice_sessions` is fetched per category by `PracticeViewModel`, gracefully falling back to `PracticeSession.mock(for:)` if the table is unseeded. `profiles` is read/written via `fetchProfile`/`upsertProfile` (uncached, RLS-protected).
- **Mock-driven:** `programs` and `CommunityCircle` on Home (`fetchPrograms()` exists but is unused); all Journal / Exercise / Recipe / Massage content (driven by `.all` arrays in `Models.swift`, pending their own tables). `JournalDetailView` stores reflections device-locally only.
- **Placeholder (unbuilt):** Circle tab (Community) — branded empty state via `TabPlaceholder`. The You tab (Profile) is now partly real (account UI + status); its "Reset onboarding" button is gated behind `#if DEBUG`.
- **Not yet built (next phases):** Sign in with Apple (needs the Apple capability/entitlement); **Phase 2 — retreat payments via Stripe** (Edge Functions create PaymentIntents from `retreats.price_usd`, webhook writes a `bookings` table, `RetreatDetailView` Reserve wired to it — retreats are real-world services so Stripe is App-Store-allowed); **membership** subscription (a "mix" of digital + real-world perks → must use StoreKit IAP).
- **No tests:** no test targets exist yet.

## Resources

Images live in `Resources/Images/` and Geist fonts in `Resources/Fonts/` (both at the **repo root**, not inside `SoulfullGatherings/`). Images are referenced by string name (e.g. `"retreat-mallorca"`, `"home-bg"`, `"soulfull-logo-white"`); the same handful of retreat photos currently double as placeholder art across Practice content. Images must also be in the asset catalog (`SoulfullGatherings/Assets.xcassets`) for `Image(_:)` to find them, and fonts must be listed in `Info.plist` `UIAppFonts` (currently the six shipped Geist weights).