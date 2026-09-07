# Soulfull Gatherings — iOS App

SwiftUI iOS app for a wellness retreat and community platform. Dark, editorial aesthetic throughout. Backend is Supabase (PostgreSQL + Storage + Auth — Sign in with Apple or email/password). Browsing is open to an anonymous guest; an account is asked for only at the first practice. Mock data still exists in `Models.swift` and is used while real Supabase tables are being seeded.

**Minimum deployment target: iOS 18.** Always use the latest Swift and SwiftUI idioms — `@Observable` over `ObservableObject`, `@Environment` over `@EnvironmentObject`, `@State` over `@StateObject`/`@ObservedObject`, typed throws, `NavigationStack` with typed `Route` enums, etc. Do not reach for deprecated patterns for compatibility — there is no older OS to support. Swift language version is pinned to 6.0 in `project.yml`.

## Build & Run

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` from `project.yml`. `project.yml` is the single source of truth for the build (target, Swift 6, iOS 18 deployment, bundle ID `com.soulfullgatherings.app`, Supabase + Stripe (`StripePaymentSheet`) SPM dependencies, Geist font resources, the Sign in with Apple entitlement, `Secrets.xcconfig` injection). Regenerate `.xcodeproj` whenever you edit `project.yml`.

> **`SoulfullGatherings/Info.plist` and `SoulfullGatherings/SoulfullGatherings.entitlements` are generated artifacts.** XcodeGen writes them from `project.yml`'s `info.properties` / `entitlements.properties` on every `xcodegen generate`, so hand-edits are silently reverted. Add or change bundle keys and entitlements in **`project.yml`**. Both are gitignored.

> Stripe is pulled from **`github.com/stripe/stripe-ios-spm`** (the slim, SPM-optimized distribution), **not** `stripe/stripe-ios` — the main repo's multi-GB history makes SPM resolution extremely slow. Don't switch it back.

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
2. **Tab level** — `App/MainTabView.swift` hosts three tabs (`MainTab`: `home`, `practice`, `you`) with the custom `BottomNav` glass bar, which builds itself from `MainTab.allCases`. The Home and Practice tabs each wrap their content in a private per-tab `NavigationStack` root (`HomeRoot`, `PracticeRoot`); the You tab renders directly with no stack. (`circle` was cut from v1 — see `AppFeatures.circleTabEnabled`; re-adding the enum case restores the tab and its nav item.)
3. **Item level** — each tab root holds a typed `Route` enum and a `@State private var path: [Route]`. `HomeRoot.Route` covers `retreatsStack`/`retreatDetail`; `PracticeRoot.Route` covers the practice session list plus journal/exercise/recipe/massage list and detail destinations. Native swipe-back works because navigation is value-based.

**Auth:** `AppState.initializeAuth()` runs from the app entry `.task`; it calls `AuthManager.initialize()` and then routes to the correct stage. **No account is needed to browse** — see *Account gate* below. `AuthManager` establishes (or restores) an **anonymous** Supabase session on launch (so catalog reads work during welcome/onboarding), then lets the user **upgrade that guest into a permanent email/password account** in place (`createAccount` calls `auth.update` on the anonymous user so the same `id` and any data carry over; a non-anonymous user falls through to `signUp`). Also exposes `signIn`, `signOut` (signs out then re-opens a fresh anonymous session so the app keeps working). Liveness is `AuthManager.State` (`initializing`, `authenticated`, `failed(String)`); identity is `isAnonymous`, `hasAccount` (= authenticated **and** not anonymous — gate paid/Reserve flows on this, not `isAuthenticated`), `email`, and `userID`. **Sign in with Apple:** `signInWithApple(idToken:nonce:fullName:)` exchanges the token from `SignInWithAppleButton` via `signInWithIdToken`. It is the **only** third-party provider — Google was built (hosted OAuth in an `ASWebAuthenticationSession`) and then deliberately removed before shipping on 2026-09-03, so there is no GoogleSignIn dependency and no web-auth flow anywhere in the app. Apple sign-in does *not* upgrade the anonymous guest — Supabase signs the Apple identity in as its own user and the guest session is replaced. Nothing user-visible is lost: onboarding answers live in `AppSettings` and `AccountViewModel.mergeProfile` reconciles them with the server row (hydrate if the row already has answers, push if it doesn't). Preserving the guest id would need `linkIdentity`, which requires manual linking enabled in the dashboard. **Email confirmation** (if enabled in Supabase) has **three** completion paths, because the link alone only works on one device. (1) *Same device*: the link deep-links back at `soulfull://auth-callback` — `SoulfullGatheringsApp`'s `.onOpenURL` calls `AuthManager.handleDeepLink(_:)`, which runs `auth.session(from:)` (PKCE) to finalize the session. (2) *Any device*: the email leads with a **numeric code** (length = the project's `mailer_otp_length`, **6** on the live project — the app pins no length and the server validates); `AccountView`'s confirm panel takes it and `AuthManager.confirmEmail(code:email:)` calls `verifyOTP`, which needs no PKCE verifier and returns a real session. (3) *Confirmed elsewhere*: opening the link on a laptop confirms the address server-side but tells this device nothing, so `AuthManager.refreshConfirmationState()` re-reads `GET /user` — polled every 5s while the confirm panel is up, and once at launch for a guest session — and rotates the token when it finds the address confirmed. **Don't reduce this to the deep link again**: the PKCE verifier lives in *this* iPhone's Keychain and `soulfull://` doesn't resolve in a desktop browser, so a link-only flow strands anyone who reads mail on a computer. **Sign in with Apple is wired** — the `com.apple.developer.applesignin` entitlement is generated from `project.yml`, and the `APPLE_ID_AUTH` capability is enabled on the App ID (verified against the App Store Connect API, 2026-09-03).

**Account gate (just-in-time).** Browsing is free; the account is asked for at the moment the user reaches for something personal. `Features/Auth/AccountGate.swift` is an `@Observable` that holds the interrupted action, raises `AccountView` as a sheet, and **replays the action** on `onDismiss` if an account now exists — so signing in never costs the user the tap they were making.

| Open to a guest | Gated on `auth.hasAccount` |
|---|---|
| Home, mood chips, ritual card | Playing a practice session (`PracticePlayerView`) |
| Retreats stack + retreat detail | Journal prompt / exercise / recipe / massage detail |
| Practice landing **and every list screen** | Reserve / checkout (already gated) |

The gate lives in `MainTabView` — one sheet for the whole shell — and is handed to `PracticeRoot` as `requireAccount: (@escaping () -> Void) -> Void`. `PracticeRoot` wraps only the four detail pushes; `PracticeListView` takes the same closure and wraps the player. Both default to `{ $0() }` so previews and any un-gated host run straight through. **Note the `@escaping` inside the function type — it is required there and easy to get wrong; without it the closure can't be stored and the build fails.**

`AccountGate` holds **only the pending action** and is not `@Observable`; `require(signedIn:_:)` returns `Bool` and the caller raises the sheet off a plain `@State` Bool, matching every other sheet here.

> **Why not a hard gate.** A required-registration wall at the end of onboarding was built first (2026-09-03) and removed the same day: it put the app in scope for **App Store Guideline 5.1.1(i)** — registration may not be required unless directly relevant to core functionality — because it blocked a browsable catalog behind a login. Gating the *doing* rather than the *browsing* keeps that argument easy to make. Don't reintroduce a gate in `AppState.initializeAuth()` or as an onboarding step.

## File Map

```
Config/
├── Secrets.xcconfig                   # Gitignored — real Supabase host + anon key + DEVELOPMENT_TEAM (never commit)
└── Secrets.xcconfig.example           # Template; copy to Secrets.xcconfig on a new machine

scripts/
├── apply-auth-emails.sh               # PATCHes ONLY the four mailer_* fields on the project's auth config
│                                      # (never `supabase config push` — that would reset every unspecified
│                                      # setting to CLI defaults, incl. anonymous sign-ins)
└── make-app-icon.swift                # Regenerates Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024², opaque)
                                       # from soulfull-logo-white on the Theme.splash gradient. Run after any brand-mark change.

supabase/                              # Backend-as-code. NOT part of the Xcode build (project.yml only sources SoulfullGatherings/ + Resources/Fonts).
├── templates/                         # Branded auth emails (confirm-signup + change-email) + README.
│                                      # Apply with scripts/apply-auth-emails.sh; the "Supabase Auth" SENDER
│                                      # name needs custom SMTP, which the README walks through.
├── migrations/
│   ├── 0001_profiles.sql              # `profiles` table + RLS + auto-create/updated_at triggers
│   ├── 0002_bookings.sql              # `bookings` table + RLS (read-only for owner; webhook writes via service role)
│   ├── 0003_retreats_public_read.sql  # retreats SELECT policy for `anon` + `authenticated` (see RLS-role gotcha below)
│   ├── 0004_retreats_group_chat_url.sql # adds `retreats.group_chat_url` (per-retreat WhatsApp invite, surfaced in the post-purchase hub)
│   ├── 0005_practice_sessions.sql     # `practice_sessions` table + RLS (anon, authenticated) + the private `practice-media`
│   │                                  # Storage bucket + seeding instructions. APPLIED but EMPTY — upload media, insert
│   │                                  # rows, and the Practice media tracks unlock with no app release.
│   ├── 0006_programs.sql              # `programs` table + RLS. APPLIED but EMPTY — until seeded, Home's Digital Retreats
│   │                                  # shelf hides itself entirely (no mock fallback).
│   ├── 0007_mallorca_dates.sql        # Moves Mallorca to 2027-07-21→26 so the date filter stops hiding the one retreat with
│   │                                  # curated brochure + PostBooking content. APPLIED.
│   └── 0008_practice_progress.sql     # `practice_plays` ledger + the `practice_progress` / `practice_creator_earnings` views.
│                                      # APPLIED 2026-09-06 and verified against the live DB (RLS isolation, the integrity
│                                      # trigger, and account-deletion anonymisation were each exercised). See "Practice progress".
└── functions/                         # Deno Edge Functions. See functions/README.md for deploy + secrets.
    ├── create-payment-intent/         # Auth'd: reads authoritative retreat price, reuses/creates Stripe customer, returns PaymentIntent + ephemeral key
    ├── stripe-webhook/                # Stripe-signed (deploy --no-verify-jwt): writes bookings on payment_intent.succeeded/payment_failed
    └── delete-account/                # Auth'd: deletes the caller's Stripe customer (best-effort) + auth user (cascades to profiles/bookings) — App Store account-deletion compliance

SoulfullGatherings/
├── SoulfullGatheringsApp.swift        # @main entry; creates AppState, injects environment, forces dark mode, kicks off auth via .task; .onOpenURL routes soulfull:// auth deep links to AuthManager.handleDeepLink
├── SoulfullGatherings.entitlements    # GENERATED by XcodeGen from project.yml's `entitlements.properties`. Sign in with Apple
│                                      # (`com.apple.developer.applesignin`). Gitignored; edit project.yml, not this file.
├── Info.plist                         # GENERATED by XcodeGen from project.yml's `info.properties` — edit project.yml, not this file.
│                                      # Gitignored (like *.xcodeproj): a fresh clone runs `xcodegen generate` before building.
│                                      # SupabaseHost/SupabaseAnonKey resolve from xcconfig; UIAppFonts (Geist); portrait-only;
│                                      # UILaunchScreen (LaunchBackground colour, no storyboard); ITSAppUsesNonExemptEncryption=false
├── PrivacyInfo.xcprivacy              # Privacy manifest — UserDefaults required-reason (CA92.1) + collected-data types.
│                                      # Covers THIS app only; Supabase/Stripe ship their own. Keep in sync with the ASC privacy answers.
├── Assets.xcassets                    # Asset catalog: images, AppIcon (1024² opaque, see scripts/make-app-icon.swift),
│                                      # LaunchBackground colour set (= Theme.bg, used by UILaunchScreen)
│
├── App/                               # App-level: global state, routing, auth, navigation shell
│   ├── AppState.swift                 # @Observable stage router (loading/welcome/onboarding/main) + lifecycle; initializeAuth() (routes on hasOnboarded alone — no account needed)/resetAll()
│   ├── AuthManager.swift              # @Observable Supabase auth; initialize() restores/opens anonymous session; createAccount (upgrades guest in place)/signIn/signInWithApple (signInWithIdToken — the only third-party provider)/signOut/deleteAccount (delete-account fn → re-anon); handleDeepLink (email-confirmation callback via PKCE session(from:)); confirmEmail (verifyOTP on the emailed code — the cross-device path) / resendConfirmation / refreshConfirmationState (re-reads GET /user so a confirmation made elsewhere lands here); exposes isAnonymous/hasAccount/email/userID/pendingConfirmation
│   ├── AppSettings.swift              # @Observable UserDefaults wrapper (didSet persistence); hasOnboarded/userName/bodyState/frequency/intentions
│   ├── RootView.swift                 # Stage switcher with opacity + motion transitions
│   ├── MainTabView.swift              # Three-tab container (home/practice/you) + private HomeRoot/PracticeRoot NavigationStacks; owns the AccountGate + its sheet;
│                                      # DEBUG `-tab <name>` launch arg opens straight to a tab
│   ├── BottomNav.swift                # Custom floating glass tab bar (@Binding current tab); builds from MainTab.allCases
│   └── ConnectionBanner.swift         # Offline / failed-session notice + working Retry; shown when AuthManager.needsRetry
│
├── Core/                              # Shared foundational code
│   ├── Models/
│   │   └── Models.swift               # All domain models + mock data (Profile, Retreat [+ optional groupChatURL from the DB `group_chat_url`], RetreatExperience [optional long-form detail content; .curated(for:) matches by name; .mallorca holds the curated brochure copy + .postBooking — the post-purchase trip: checkout summary, to-do's, packing, 1:1 GuideOffers, mocked assistant replies], Program, CommunityCircle, PracticeCategory, MediaKind, MediaItem, PracticeSession, PracticeMenuItem, JournalPrompt, ExerciseStep, Exercise, Recipe, Massage, IntentionOption, BodyStateOption, FrequencyOption, MoodChip)
│   ├── DesignSystem/
│   │   ├── Theme.swift                # Brand colors, gradients, Geist typography helpers, shape constants + Color(hex:)
│   │   ├── Components.swift           # SGPrimaryButton, GlassCard, SectionLabel, PhotoBackdrop (blur/darken/pan/topScrim; image contained in a Color overlay so scaledToFill can't inflate layout; no grain — grain over photography was pulled as too busy), .onPhoto() (type-over-photography halo), CircleIconButton, TabPlaceholder, PulseModifier, BreathingModifier (.breathing — 5–6s idle loop)
│   │   ├── Shaders.metal              # Stitchable shader suite: filmGrain, aurora, shimmer, noiseDissolve, ripple
│   │   ├── ShaderFX.swift             # Wrappers for Shaders.metal (feature code never touches ShaderLibrary): .filmGrain, AuroraBackground, .shimmer(on:), NoiseDissolve Transition (+ .soulStage), .ripple, editorialRise/Page(/Soft) transitions. All Reduce Motion-aware.
│   │   ├── SoulGlass.swift            # .soulGlass(in:)/.soulGlassCapsule/.soulGlassCard — real Liquid Glass on iOS 26+, material+hairline on 18–25. The only place that branches on OS.
│   │   ├── Pressable.swift            # SoulPressableStyle (.soulPressable/.soulPressableChip/.soulPressableQuiet) + PressableCard — unified touch physics (spring squish + haptic on touch-down)
│   │   ├── PinchBrowse.swift          # .pinchBrowsable(zoomedOut:) — interactive pinch zoom-out for catalogs (scrub → spring commit); pair w/ LazyVGrid column morph + a toggle button
│   │   └── Parallax.swift             # .listReveal() row-entrance scrollTransition
│   ├── Services/
│   │   ├── SupabaseConfig.swift       # Loads + validates Supabase host/anon key from Info.plist (Bundle.main); ConfigError (missingKey/malformedHost)
│   │   ├── SupabaseService.swift      # Actor data layer: nonisolated client, 5-min TTL caches, fetchRetreats/Programs/PracticeSessions, fetchProfile/upsertProfile/fetchBooking (uncached), recordPracticePlay/fetchPracticeProgress (uncached), signedMediaURL, invalidateCache
│   │   ├── LocalUserStore.swift       # @Observable per-member namespace over UserDefaults (`sg.u.<user id>.…`) for data that never
│   │   │                              # leaves the device — journal reflections, trip checklists. adopt(userID:isAnonymous:) hands a
│   │   │                              # guest's data forward when they become a member; purgeCurrentScope() on account deletion.
│   │   ├── PracticeProgressStore.swift # @Observable singleton over `practice_progress`: refresh/clear, progress(kind:contentID:),
│   │   │                              # resumable (the Continue card), streakDays, practicesThisWeek, record(...) (fire-and-forget)
│   │   ├── PaymentService.swift       # @MainActor Stripe façade: createPaymentIntent (calls Edge Function) + presentPaymentSheet (StripePaymentSheet); publishable key comes from the function, never stored in-app
│   │   └── AppError.swift             # App-level LocalizedError enum (configurationMissing/authFailure/networkFailure/unknown)
│   └── Utils/
│       ├── Log.swift                  # os.Logger facade (auth/data/media/payment). Replaced every print(); interpolation is
│       │                              # redacted by default in Release — mark safe values `\(x, privacy: .public)`.
│       ├── Haptics.swift              # @MainActor UIKit haptic facade with cached generators (tap/bump/select/success/prepare)
│       └── ArtworkTones.swift         # CIAreaAverage → (top/mid/base) tone triple from an asset; grades the player's aurora to the artwork
│
└── Features/                          # One folder per feature/tab; each owns its views + VMs
    ├── Auth/
    │   ├── AccountGate.swift          # Just-in-time gate: holds the interrupted action and replays it on dismiss if an account now exists. require(signedIn:_:) -> Bool (caller raises the sheet) / resume(signedIn:)
    │   ├── AccountView.swift          # Create-account / sign-in sheet (You tab, Reserve, and the practice gate). Sign in with Apple first, "or" rule, then the glass email form; confirm-your-email panel when confirmation is pending — code field (`.oneTimeCode` autofill, no hardcoded length), Confirm, Send a new code (30s cooldown), Use a different sign-in — and it dismisses automatically once hasAccount flips
    │   ├── AppleSignInButton.swift    # Native SignInWithAppleButton + AppleNonce (random + SHA-256) for replay protection. Pure UI — hands the credential back to the caller
    │   └── AccountViewModel.swift     # @Observable; form state + validation; confirmCode/resendCode + beginConfirmationWatch (VM-owned Task, so dismissing mid-flight can't cancel the profile write); calls AuthManager then syncs profile (push local answers on create / hydrate on sign-in / mergeProfile for social, which can't tell new from returning). Treats Apple + web-session cancels as .cancelled, not an error
    ├── Welcome/
    │   └── WelcomeView.swift          # Splash (logo breathing) + 3 explainer slides → routes to onboarding
    ├── Onboarding/
    │   ├── OnboardingView.swift       # 4-question flow (name/intention/state/frequency) + finish screen; step sub-views inline. No account step — that moved to AccountGate
    │   └── OnboardingViewModel.swift  # Step state machine, per-step validation (canAdvance), next/back, commit to AppSettings
    ├── Home/
    │   ├── HomeView.swift             # Dashboard: greeting (+ streak line at ≥2 days), mood chips, Continue card (when something is half-done), ritual card, retreat glimpse, programs shelf → opens Retreats
    │   └── HomeViewModel.swift        # Greeting from hour, mood selection, loads retreats + programs from Supabase (circles still mock)
    ├── Retreats/
    │   ├── RetreatsStackView.swift    # Viewport-aligned scrolling name stack with crossfading photo backdrop; loadError retry
    │   ├── RetreatsViewModel.swift    # Retreat array + active index, loading/error state, fetches from Supabase
    │   ├── RetreatDetailView.swift    # Scroll-graded editorial spread. If the retreat resolves a RetreatExperience (inline mock, or RetreatExperience.curated(for:) matched by name) it renders the full brochure story (invitation, who-it's-for, the four elements, member's word, guides, stay & inclusions) and prefers the experience's brochure date/cover line; else the concise pull-quote/days/details fallback. Reserve gated on auth.hasAccount → AccountView sheet; else pushes the checkout review (onCheckout); once paid the CTA flips to "View your experience" (onOpenExperience → hub). Closures wired from MainTabView.HomeRoot
    │   ├── RetreatDetailViewModel.swift # @Observable; loadExistingBooking (reflect a paid booking) + reserve() (PaymentIntent → PaymentSheet → phase). Reused by RetreatCheckoutView for the actual charge
    │   └── PostPurchase/              # Reserved-retreat experience — the UX team's WARM-ESPRESSO direction (terracotta/olive/gold on espresso, all-Geist), a retreat-specific palette distinct from the app-wide Theme. Routed via HomeRoot.Route (retreatCheckout/Experience/Todos/Packing/Guides/Chat). DEBUG launch args -preview-checkout/-experience/-todos/-packing/-guides/-chat render each in isolation.
    │       ├── RetreatPalette.swift            # Warm-espresso palette (espresso/cream/terracotta/olive/gold) — mirrors the inline .mb tokens in the design-system mallorca-*/retreat-* cards; used ONLY by these screens, not the global Theme
    │       ├── RetreatTripStore.swift          # @Observable singleton; device-local (UserDefaults) to-do completion + 1:1 bookings, keyed by retreat id (sg.trip.todos / sg.trip.sessions). Packing reuses to-do storage with pack- prefixed ids
    │       ├── RetreatCheckoutView.swift       # Order-summary + due-today review → Stripe PaymentSheet via RetreatDetailViewModel.reserve() (NO raw card fields); onReserved → experience hub
    │       ├── RetreatExperienceHubView.swift  # Welcome hub: hero, greeting, featured to-do card (live progress), experience grid; group-chat tile opens retreat.groupChatURL (WhatsApp)
    │       ├── RetreatTodosView.swift          # Pre-retreat checklist (RetreatTripStore-backed) + "Go to my home"
    │       ├── PackingListView.swift           # Packing checklist (RetreatTripStore-backed)
    │       ├── RetreatGuidesView.swift         # 1:1 booking — joins RetreatExperience.guides with PostBooking.offers; slot pick → confirmation (RetreatTripStore)
    │       ├── RetreatAssistantView.swift      # Concierge chat UI (bot/user bubbles, typing dots, suggestion chips, composer — plain-fill TextField per rendering gotcha #1)
    │       └── RetreatAssistantViewModel.swift # @Observable; MOCKED replies (keyword match + fallback + simulated typing) — no backend / Claude API yet
    ├── Practice/
    │   ├── PracticeView.swift         # Landing: scrolling cards for media categories (Somatic/Breathwork/Meditation) + menu items; onSelect callback
    │   ├── PracticeShared.swift       # Shared chrome: PracticeBackBar, PracticeListScaffold, NumberedStepRow, ProgressRule (hairline % bar)
    │   ├── PracticeActivity.swift     # PlaybackReporter (counts MEDIA time, not wall-clock or scrub position; 20s heartbeat + resume point)
    │   │                              # and .practiceActivity(_:enabled:completedWhen:) for the written libraries (dwell-based)
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
        └── ProfilePlaceholder.swift   # You tab: greeting + intentions + account status; Create account/Sign in (→ AccountView sheet) when guest, Sign out + Delete account (confirmationDialog → AuthManager.deleteAccount) when signed in; dev-only "Reset onboarding" gated behind #if DEBUG; custom layout, not TabPlaceholder
```

> Geist fonts live in `Resources/Fonts/` at the **repo root**, not under `SoulfullGatherings/`. `project.yml` adds `Resources/Fonts` as a resources build phase. All images are managed through `SoulfullGatherings/Assets.xcassets`.

## Design System

All brand values live in `Theme.swift` (a static-only `enum` namespace). Use `Theme.*` constants — never hardcode colors or font sizes. Colors are pre-converted from oklch design tokens to sRGB by hand; if tokens change they must be manually recalculated here.

| Token | Usage |
|---|---|
| `Theme.bg` / `Theme.bgDeep` | Near-black canvas (faint olive tint) |
| `Theme.surface` | Card fills |
| `Theme.ink` | Warm cream — primary text |
| `Theme.inkSoft` | Muted cream — secondary text |
| `Theme.muted` | Tertiary / metadata text — **on glass/solid only** |
| `Theme.inkOnPhoto` | Body copy laid directly on a photo (ink @ 0.92) |
| `Theme.accent` / `Theme.accentSoft` | Olive-green brand accent |
| `Theme.honey` | Amber glow for selected states |
| `Theme.line` / `Theme.glassBorder` / `Theme.glassBorderHigh` | Hairline / glass strokes |
| `Theme.headline(_:weight:)` | Headline font (Geist at requested weight) |
| `Theme.body(_:weight:)` | Body / UI font (Geist at requested weight) |
| `Theme.eyebrow(_:)` | Small tracked caps (Geist Regular) |

- **Typography:** Geist family ships Thin/Light/Regular/Medium/SemiBold/Bold (registered in `Info.plist` `UIAppFonts`); heavier weights fall back to Bold, lighter to Regular. There is **no serif/SF Pro split — everything is Geist.** Headlines use negative `kerning` (e.g. `-0.2`/`-0.3`); body/eyebrow use positive `tracking` (2–3). `Text.sgEyebrow()` applies font + tracking + uppercase + color in one call.
- **Glass surfaces:** `.ultraThinMaterial` + a `Theme.glassBorder` `strokeBorder`. `GlassCard` wraps this; `CircleIconButton` is the smaller glass chrome button. `SGPrimaryButton` is a ghost/fill pill using a `DragGesture(minimumDistance: 0)` for immediate press feedback.
- **Photo backdrops:** `PhotoBackdrop(imageName:blur:darken:)` — solid `Theme.bg` floor, blurred/saturated image, vignette. Reused everywhere; `blur` and `darken` vary per screen.
- **Type over photography (one rule, whole app).** The vignette is at its lightest up top (0.18) — exactly where every screen puts its header — so cream type over a bright sky washed out (it was reported first on Practice's "Choose a way in", and Home's greeting was worse). Three parts, and they belong together: `PhotoBackdrop` draws a **`topScrim`** (default 0.45 fading out over 340pt; pass `topScrim: 0` for a screen whose top is deliberately empty); photo-backed **text blocks carry `.onPhoto()`** (a tight shadow for edge definition + a wide halo, both invisible over dark ground, so it's safe anywhere); and the palette shifts — **eyebrows use `Theme.inkSoft`, never `Theme.muted`** (which sinks into the scrim), **sublines use `Theme.inkOnPhoto` at `Theme.body(14)`**. Type on glass or a card keeps `muted`/`inkSoft` as-is — the surface is its own ground. `.onPhoto()` goes on **text only**: a shadow over a UIKit-backed `TextField`/`TextEditor`/video is gotcha #1 territory, so wrap the copy, not the container holding the field. `RetreatDetailView`'s hero has no backdrop to scrim, so its own gradient holds ~0.22 through the middle instead of falling to 0.08.
- **Shape constants:** `Theme.cardRadius` (22), `Theme.pillRadius` (999 / Capsule).
- `PulseModifier` animates forever (`autoreverses`) — use only for persistent live indicators.

## Backend

**Supabase** hosts content data (PostgreSQL), media (Storage), and the user session (Auth — anonymous guests upgradable to email/password accounts). The Swift SDK (`import Supabase`, `@preconcurrency`) is added via SPM.

**Migrations** live in `supabase/migrations/` at the repo root (run them in the dashboard SQL editor or via `supabase db push`). They are **not** part of the Xcode build — `project.yml` only sources `SoulfullGatherings/` and `Resources/Fonts`, so adding SQL needs no `xcodegen generate`.

**`SupabaseService` is an actor singleton.** It exposes `client` `nonisolated` (so `AuthManager` can reach the `SupabaseClient` without an actor hop) and maintains three independent in-memory caches (retreats, programs, practice sessions) each with a 5-minute TTL. There is no automatic invalidation — call `invalidateCache()` on logout/explicit refresh. Bootstrap is fatal: if `SupabaseConfig.make()` throws (missing/placeholder credentials) the app crashes at startup with setup instructions.

**Credentials flow:** `Config/Secrets.xcconfig` → build settings → `Info.plist` (`SupabaseHost`, `SupabaseAnonKey` via `$(SUPABASE_HOST)` / `$(SUPABASE_ANON_KEY)`) → `Bundle.main` → `SupabaseConfig` → `SupabaseService`. Never hardcode credentials in Swift source. The same xcconfig also carries `DEVELOPMENT_TEAM` (the Apple Team ID, injected into build settings) — empty builds fine for the simulator, but archiving for the App Store needs a real ID.

- `Config/Secrets.xcconfig` is gitignored and contains the real anon key. Copy `Secrets.xcconfig.example` to set up a new machine.
- `SUPABASE_HOST` stores the host only (e.g. `abc123.supabase.co`) — no `https://` prefix because `//` is a comment delimiter in xcconfig. `SupabaseConfig` rejects empty values and anything starting with `YOUR_`, and validates the host builds a usable `https://` URL.

**Database tables** (snake_case columns, mapped by private `…Row` DTO `CodingKeys` in `SupabaseService.swift`; each Row has a computed property returning the domain model):

| Table | Key columns | Fetch | Limit |
|---|---|---|---|
| `retreats` | `id`, `name`, `country`, `start_date`, `end_date`, `max_guests`, `price_usd`, `tags` (array), `blurb`, `image_url`, `tone_top`, `tone_mid`, `tone_base`, `group_chat_url` (nullable; per-retreat WhatsApp invite) | `fetchRetreats()` — **filters `end_date >= today`**, order by `start_date` | 50 |
| `programs` | `id`, `title`, `lead`, `date_range`, `days`, `image_url` | `fetchPrograms()` (order by `title`) — now called by `HomeViewModel`; empty result hides the shelf | 50 |
| `practice_sessions` | `id`, `category` (`somatic`/`breathwork`/`meditation`), `title`, `lead`, `media_kind` (`audio`/`video`), `storage_path`, `duration_seconds`, `image_url`, `blurb` | `fetchPracticeSessions(category:)` (filtered by `category`); `availablePracticeCategories()` returns which categories have rows, and never throws | 100 |
| `profiles` | `id` (uuid = `auth.users.id`), `email`, `full_name`, `intentions` (text[]), `body_state`, `frequency`, `stripe_customer_id` (server-only), `created_at`, `updated_at` | `fetchProfile(id:)` / `upsertProfile(_:)` (uncached) | 1 |
| `bookings` | `id`, `user_id`, `retreat_id`, `amount_usd`, `currency`, `status` (`pending`/`paid`/`failed`/`refunded`), `stripe_payment_intent_id`, `created_at`, `updated_at` | `fetchBooking(retreatID:userID:)` (uncached) | 1 |
| `practice_plays` | `id`, `user_id` (nullable), `content_kind` (`session`/`massage`/`journal`/`exercise`/`recipe`), `content_id`, `content_title`, `creator`, `category`, `seconds_played`, `position_seconds`, `duration_seconds`, `completed`, `client_event_id`, `started_at` | `recordPracticePlay(...)` — upsert on `(user_id, client_event_id)` (uncached) | — |
| `practice_progress` *(view)* | `user_id`, `content_kind`, `content_id`, `content_title`, `creator`, `category`, `position_seconds`, `duration_seconds`, `total_seconds_played`, `completed`, `play_count`, `last_played_at` | `fetchPracticeProgress(userID:)` (uncached) | 200 |

- `RetreatRow` parses `start_date`/`end_date` with a per-call `DateFormatter` (`yyyy-MM-dd`, `en_US_POSIX`); `Retreat` then derives its display `when` string and `durationDays`/`priceFormatted` itself.
- **Tone colors** are hex strings (e.g. `#728FA5`) decoded via `Color(hex:)` (extension in `Theme.swift`).
- `CommunityCircle` has **no** Supabase fetch yet — it is mock-only (`CommunityCircle.mock`). `programs` **is** fetched by `HomeViewModel` (no mock fallback — an empty table hides the shelf).

> **RLS role gotcha (bit us once, will again):** anonymous guests are **not** the `anon` Postgres role — `signInAnonymously()` issues a real JWT with `role: authenticated` (`is_anonymous: true`). So requests hit RLS as `authenticated`, the same role as permanent accounts. **Public/catalog tables must grant SELECT to *both* `anon` and `authenticated`** (or `to public`); a policy scoped `to anon` only returns 0 rows once anonymous sign-in is on (that's exactly why `0003_retreats_public_read.sql` exists). Write policies that omit a `to` clause default to `public`, which is why `profiles`/`bookings` were unaffected. `programs`/`practice_sessions` already follow this (`for select to anon, authenticated using (true)`); give any new catalog table the same. `practice_plays` is the exception and is deliberately scoped `to authenticated` with `auth.uid() = user_id` — it is per-member data, not catalog.
- **`profiles` is protected by row-level security** (`auth.uid() = id` for select/insert/update; no delete; no client write to `stripe_customer_id`). A row is auto-created by an `auth.users` insert trigger (covers anonymous guests too), and `updated_at` is bumped by a trigger. The app only ever reads/writes its **own** row. `upsertProfile` deliberately omits `stripe_customer_id` and timestamps so it never clobbers server-managed columns. Account creation pushes local onboarding answers up; sign-in hydrates `AppSettings` from the row. **Email confirmation:** when Supabase "Confirm email" is on, the anonymous→permanent upgrade completes only once the address is verified — by the emailed code (`verifyOTP`, works from any device), by the emailed link on this iPhone (`soulfull://auth-callback` → `AuthManager.handleDeepLink`, PKCE `session(from:)`), or by `refreshConfirmationState` noticing a confirmation made elsewhere. `AccountView` shows the confirm panel after sign-up and auto-dismisses once `hasAccount` flips. Note which *template* fires: the guest upgrade is `auth.update(email:)`, i.e. an email **change**, so most users receive the *Change Email Address* email, not *Confirm signup* — both are branded in `supabase/templates/`. (With confirmation off, the upgrade completes immediately and the panel is skipped.)

> **Required Supabase Auth dashboard settings (the app silently breaks without them):** (1) **Anonymous sign-ins = ON** — the app boots a guest session and upgrades it in place; if off, launch lands in `AuthManager.State.failed` with no session and both retreat reads and account creation misbehave. (`createAccount` falls back to `signUp` when there's no anonymous session, but the guest-upgrade UX needs it on.) (2) **Confirm email** — supported either way; when ON, you **must allow-list the redirect URL** under Authentication → URL Configuration → Redirect URLs: add `soulfull://auth-callback` (must match `SupabaseService.authRedirectURL` and the `CFBundleURLTypes` scheme in `project.yml`), or Supabase ignores the redirect and the email link won't reopen the app. (3) **Custom SMTP** — the built-in email service sends as `Supabase Auth <noreply@mail.app.supabase.io>` (that sender is not editable on any plan) and is rate-limited to a handful of emails per hour project-wide, which is explicitly not for production. Set Project Settings → Authentication → SMTP with sender name `Soulfull Gatherings`, and apply the branded templates (`supabase/templates/`, `scripts/apply-auth-emails.sh`). (4) **Apple provider = ON** with the app's bundle ID (`com.soulfullgatherings.app`) in *Client IDs*, and *Secret Key* left blank (it is only used for Apple's web OAuth flow, which this app doesn't use) — the native token flow verifies the token's `aud` against the Client IDs list, so an empty field rejects every Apple sign-in. **A misconfigured Apple provider breaks every Apple sign-in, which is the primary way into an account — verify it before shipping.** No Google provider is needed; Google sign-in was removed on 2026-09-03.

**Payments (Phase 2 — Stripe, retreat reservations).** Retreats are real-world services, so Stripe (not Apple IAP) is the correct, App-Store-allowed rail. Flow: `RetreatDetailView` Reserve → (gate on `auth.hasAccount`, else present `AccountView`) → `PaymentService.createPaymentIntent` invokes the **`create-payment-intent`** Edge Function (authoritative price read server-side from `retreats`; reuses/creates the Stripe customer on `profiles.stripe_customer_id`) → `PaymentService.presentPaymentSheet` shows Stripe's `PaymentSheet` → on success the **`stripe-webhook`** function writes the `bookings` row with the service role. The client **never** writes payment state and never holds Stripe secrets — even the publishable key is returned by the function. `bookings` RLS is read-only for the owner. Stripe keys live only in Supabase function secrets (`STRIPE_API_KEY` — a **restricted** `rk_` key needing **Customers + PaymentIntents + Ephemeral Keys** write; the ephemeral-key permission is separate and easy to miss — plus `STRIPE_PUBLISHABLE_KEY` / `STRIPE_WEBHOOK_SECRET`). Server calls omit `payment_method_types` (dynamic payment methods) and use the account-default API version. The app sends its `STPAPIClient.apiVersion` so the function mints the ephemeral key with the matching version — no server/SDK version coordination needed. See `supabase/functions/README.md` for deploy steps + restricted-key permissions.

**Practice media** lives in a Supabase **Storage** bucket (default `practice-media`); `practice_sessions.storage_path` stores only the bucket-relative path. `SupabaseService.signedMediaURL(path:bucket:expiresIn:)` (default 1-hour expiry) turns a private path into a time-limited signed URL. `PracticePlayerView` plays a `storagePath` that is an absolute `http(s)` URL directly (without signing) and signs everything else; the `.mock` sessions carry an **empty** `storagePath` and are preview fixtures only (the old public sample URLs were removed — see the Practice note under App Store Submission).

**Practice progress (and creator payouts).** Every practice a member opens is recorded server-side, because the rows are two things at once: the member's "Continue where you left off", and **the record content-creator payouts are calculated from**. `supabase/migrations/0008_practice_progress.sql` defines one append-mostly table and two views over it — a single source of truth, so the resume point and the payout total can never disagree.

- **`practice_plays`** — one row per playback/reading session, addressed by a client-minted `client_event_id` so a heartbeat retry can't pay a creator twice. `content_title` / `creator` / `category` are **snapshots**: retitling a session or reassigning a guide must not move historical payouts.
- **Integrity is enforced in the DB, not the client.** A `before insert or update` trigger freezes the identity columns, keeps `seconds_played` monotonic, latches `completed`, and clamps consumption to the practice's own length. There is no delete policy at all — deleting a play would erase a creator's earnings. All four were exercised against the live table: a replayed heartbeat can't rewind the count, a client claiming 99999s against a 600s track is clamped to 600, and re-pointing a play at another creator is silently reverted.
- ⚠️ **The trigger must not freeze `user_id` unconditionally** — a lesson from the first version, which did. `ON DELETE SET NULL` performs an *UPDATE*, so a blanket `new.user_id := old.user_id` silently reverts the FK's own anonymisation: the deleted member's uuid stays bolted to their history and the foreign key ends up violated. The freeze is therefore conditional on `new.user_id is not null`. The gap that opens is closed by RLS, not by the trigger: `with check (auth.uid() = user_id)` runs *after* the trigger, and `auth.uid() = NULL` is NULL rather than true, so a client cannot null its own row to escape RLS. Verified both ways on the live table.
- **Account deletion anonymises rather than cascades.** `user_id` is nullable with `on delete set null`, so when a member deletes their account the play survives without them (the creator still earned it) and RLS then hides it from every client. This is why `delete-account` doesn't take the ledger with it.
- **`practice_progress`** (view, `security_invoker = on`) is what the app reads. ⚠️ That setting is load-bearing — without it the view runs as its owner, bypasses RLS on `practice_plays`, and every member reads everyone else's history.
- **`practice_creator_earnings`** (view, owner rights **on purpose**, so it can aggregate across all members) is the payout report. It is `revoke`d from `anon` and `authenticated`; those GRANTs are the only thing between it and a full history leak. **Never grant it to a client role.**
- **Measurement.** `PlaybackReporter` counts *media* time (not wall-clock, not the scrubber), so seeking to the end banks nothing and a paused player accrues nothing; it heartbeats every 20s so a force-quit loses little. The written libraries have no transport, so `.practiceActivity(_:)` measures time on screen instead — a journal prompt counts as done once something is written against it, the others after 45s. A massage with media reports through the player and passes `enabled: false` to the modifier so one sitting isn't counted twice.
- **Client-reported seconds are client-reported.** The trigger bounds inflation; it doesn't eliminate it. If payouts ever need to be defensible against a determined attacker rather than a buggy client, move the write behind an Edge Function that cross-checks the Storage access log.

**Per-member device-local data (`LocalUserStore`).** Some things deliberately never leave the phone — journal reflections above all, since the privacy policy makes that an explicit promise, plus the post-purchase trip checklists. They are namespaced **per member** under `sg.u.<user id>.…`, not per device. `AuthManager.apply(_:)` calls `adopt(userID:isAnonymous:)` on every identity refresh (cheap no-op when unchanged); it hands a guest's data forward when that guest becomes a member, sweeps an abandoned guest scope, and leaves a permanent account's data alone in case they sign back in. `deleteAccount()` calls `purgeCurrentScope()` — the confirmation dialog promises to delete "saved data", and before this it deleted the server row and left the writing on the phone. **A flat `sg.journal.<id>` key is a bug, not a shortcut:** it let two people sharing an iPhone read each other's reflections.

**Adding a new fetch:** add a private `Codable` `…Row` DTO inside `SupabaseService.swift` with `CodingKeys` mapping snake_case → camelCase and a computed property returning the app model. Then add a `func fetch…() async throws -> [T]` (consider a cache + TTL if it mirrors the existing pattern). Wrap/surface failures through `AppError`.

## Design System & Motion (2026-06 overhaul)

See `docs/DESIGN.md` for the full direction ("quiet luxury, editorial"). The short version:

- **Glass:** every glass surface goes through `SoulGlass` (`.soulGlass(in:)`/`.soulGlassCapsule`/`.soulGlassCard`) — real `glassEffect` on iOS 26+, material+hairline below. Never branch on OS in feature code.
- **Touch physics:** every tappable surface is a `Button` styled with `SoulPressableStyle` (or wrapped in `PressableCard`) — spring squish + haptic on touch-down. Don't add `onTapGesture` to cards.
- **Shaders** only via `ShaderFX` wrappers (grain/aurora/shimmer/dissolve/ripple); all are Reduce Motion-aware.
- **Navigation delight:** pushes from cards use `navigationTransition(.zoom)` with `matchedTransitionSource`; tab roots report pushes via a `navHidden` binding so `BottomNav` bows out on detail screens. Retreats & Practice support pinch-out into "catalog" contact sheets (always paired with a visible grid-toggle button for discoverability).
- **`SoulfullUITests` is back** (re-added 2026-09-03 to diagnose gotcha #5, which was invisible to inspection and to two rounds of reasoning). One file, `AccountGateTests.swift`, drives the account gate end to end. Run it with:
  ```bash
  xcodebuild test -project SoulfullGatherings.xcodeproj -scheme SoulfullGatherings \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -resultBundlePath build/x.xcresult -only-testing:SoulfullUITests
  ```
  Screenshots come out via `xcrun xcresulttool export attachments --path build/x.xcresult --output-path build/attach` (map names through `manifest.json`). **Reach for this whenever a control "doesn't work"** — the accessibility dump (`app.debugDescription`) reports real hit frames, which is what exposed the 11pt button. The target is scoped `SoulfullUITests: [test]` in the scheme, so archives don't build it.

**Rendering gotchas that have actually bitten this codebase — re-read before adding effects:**
1. **Metal effects (layerEffect/colorEffect/distortionEffect, incl. disabled ones) over UIKit-backed views** (NavigationStack, TextField, video) render the yellow ⃠ placeholder. Blur-carrying transitions count (blur(0) still attaches a filter). Keep shader/blur effects on pure-SwiftUI leaf subtrees; use `editorialPageSoft`/plain transitions around platform views.
2. **`visualEffect` offsets/scales escape ancestor clips** — scroll-parallax imagery inside clipped cards bleeds outside the card. Scroll-driven image motion only on full-bleed surfaces; cards animate as whole units (`listReveal`).
3. **`scaledToFill` grows layout, not just drawing** — an unconstrained fill image inflates its ZStack and pushes siblings offscreen (capsules render as full-width bands, buttons land past the screen edge). Contain fill images in a `Color.clear.overlay { … }.clipped()` (as `PhotoBackdrop` does).
4. GeometryReader inside an HStack over-claims width; prefer leading-anchored `scaleEffect` fills (see onboarding progress bar).
5. **An `Image` stretched by `.frame(width:height:)` only hit-tests its drawn glyph.** The surrounding area is inert unless something fills it or you declare `.contentShape(...)`. `CircleIconButton` had no content shape: on iOS 18–25 `.soulGlass` fell back to `.background(.ultraThinMaterial)`, which *is* hit-testable and hid the flaw, but on iOS 26 it resolves to `glassEffect`, which contributes no hit-testable fill — leaving every circular icon button in the app an ~11pt target inside a 38pt circle. Symptom: taps near the edge silently do nothing, and the accessibility frame reports the glyph size rather than the button's. It surfaced as the account sheet's close button "not working". Fixed with `.contentShape(Circle())`; **check the accessibility frame, not the visual frame, when a button feels dead.**

## Design ↔ Code Sync (Claude Design mirror)

`design-system/` (repo root) is an HTML/CSS **mirror** of the app's UI, pushed to a **Claude Design** project where the UX team edits the design visually. It is **not** part of the Xcode build (`project.yml` only sources `SoulfullGatherings/` + `Resources/Fonts`). `design-system/README.md` holds the full Swift↔CSS token/component map; the Claude Design **projectId is `76dcee6b-dc46-486b-abb7-a0c06852f1fb`**.

**`design-system/` is the single reconciliation point** between code and Claude Design. There are three flows, and only the first is automatic:

1. **Code → local mirror (do this in the same change).** When you change *design-relevant* code, update the matching `design-system/` file(s) in the **same edit/commit** so the local mirror never drifts. Design-relevant = `Theme.swift` (tokens → `shared/tokens.css`), `Components.swift`/`BottomNav`/`SoulGlass`/onboarding `OptionCard`/`PracticeShared` (→ `shared/app.css`), or a screen's layout/copy/structure in `Features/**` (→ the matching `screens/*.html`). Pure logic/backend/auth/payment changes with **no visual effect are exempt** — don't touch the mirror for those. Keep the 1:1 mapping in `README.md` intact; if you add a new screen, add a new `@dsCard` HTML card for it.
2. **Local mirror → Claude Design (deliberate, never automatic).** Push with `/sync-design push` (see `.claude/commands/sync-design.md`). Push is **incremental — only the changed cards — never a wholesale re-push**, because the UX team edits these cards and a blanket push clobbers their work. Pushing is outward-facing (writes to claude.ai): **pull/check first and confirm before pushing.** Hooks/scripts cannot push — the `DesignSync` tool needs a live session.
3. **Claude Design → code (deliberate).** `/sync-design pull` reads the team's edits back into `design-system/`, surfaces them as a diff, then ports the deltas to Swift via the `README.md` token map (e.g. a changed `--honey` hex → recompute `Theme.honey`'s RGB 0–1).

After a design-relevant code change, update the local mirror automatically (flow 1), then **remind the user** that `/sync-design push` is needed to publish to Claude Design — don't push unprompted.

## Key Conventions

- `@Observable @MainActor` on all ViewModels and app-level singletons (`AppState`, `AppSettings`, `AuthManager`). No `ObservableObject`/`@Published`.
- Haptics are mandatory on every interactive tap: `Haptics.tap()` for secondary, `Haptics.bump()` for primary CTAs, `Haptics.select()` for scroll/toggle updates, `Haptics.success()` for confirmations; `Haptics.prepare()` to warm the engine on gesture start. `SoulPressableStyle` fires `tap` on touch-down — actions using it shouldn't double-fire.
- Navigation is value-based (`NavigationStack` + typed `Route` enums per tab root), not `NavigationLink` with destinations.
- All onboarding answers are validated before `canAdvance` returns `true`; never allow advancing with empty state. The step machine has 5 cases but `questionCount = 4` (the `finish` case is not a question).
- Mock data is defined as static `.mock` / `.mock(for:)` / `.all` properties on model types in `Models.swift`.
- **Anything private and device-local goes through `LocalUserStore`, never a flat `UserDefaults` key.** It namespaces per member (`sg.u.<user id>.…`), which is what stops two people sharing a phone from reading each other's journal, and what makes "delete my account" actually delete the writing. `AppSettings` (below) is the exception: onboarding answers are device preferences, not private content, and are copied to `profiles` on sign-up anyway.
- **Practice history is server-side, never local.** `PracticeProgressStore` → `practice_plays`. It is not just UX state: it is the record creator payouts are drawn from, so it has to survive a reinstall. Never add a local mirror as the source of truth.
- **Persisted user settings live in `AppSettings`, not `@AppStorage`** — properties are backed by `UserDefaults` with `didSet` writes. All keys are prefixed `sg.` (`sg.hasOnboarded`, `sg.userName`, `sg.bodyState`, `sg.frequency`, `sg.intentions`).
- `AppSettings.intentions` is exposed as a `Set<String>` but serialized to a comma-joined string (`intentionsRaw`) — always read/write the `Set` property, never `intentionsRaw` (which is `private`).
- Domain models are value types conforming to `Identifiable` + `Hashable` (keyed on `id`) for `NavigationStack` use. Durations are stored in seconds (`durationSeconds`) with a `.durationLabel` computed property.
- **Browsing never requires an account.** Gate individual *actions* through `AccountGate`, never the route into `.main` or a whole tab — see the 5.1.1(i) note above.
- **Gate paid / account-only flows on `auth.hasAccount`, never `auth.isAuthenticated`** — the latter is true for anonymous guests. Read/write money or entitlement state server-side only (RLS for reads; webhooks via service role for writes); never trust the client.

## App Store Submission

Full audit with per-item evidence and fixes: **`docs/APP-STORE-READINESS.html`** (2026-08-31, verified against the repo, the compiled Release bundle, and the live Supabase project).

**Build-level blockers are cleared** — the app now has an icon, a launch screen, a signing hook, a privacy manifest and an encryption declaration:

| Item | State |
|---|---|
| App icon | `AppIcon.appiconset/AppIcon.png`, 1024², opaque, no alpha. Regenerate with `swift scripts/make-app-icon.swift`. The mark is the **"SOUL" block only** — the "full" script is hairline (4–20px of ink per row vs SOUL's 42–258) and dissolves below ~120px. |
| Launch screen | `UILaunchScreen` dict + `LaunchBackground` colour set (= `Theme.bg`). The old `UILaunchStoryboardName: LaunchScreen` pointed at a file that never existed. **Don't reintroduce it.** |
| Signing | `DEVELOPMENT_TEAM` flows from `Secrets.xcconfig`; `CODE_SIGN_STYLE: Automatic`. Fill in the Team ID before archiving. |
| Privacy manifest | `SoulfullGatherings/PrivacyInfo.xcprivacy` — `UserDefaults` / `CA92.1` plus collected-data types. Onboarding answers are declared `OtherDataTypes`, **not** Health; revisit if the questions become clinical. |
| Export compliance | `ITSAppUsesNonExemptEncryption: false` in `project.yml`. |
| Sign in with Apple | `com.apple.developer.applesignin` entitlement generated from `project.yml`; the `APPLE_ID_AUTH` capability is enabled on the App ID (verified 2026-09-03). It is the only third-party login, which satisfies Guideline 4.8 outright. Still give the reviewer a demo account — browsing is open, but no practice can be opened without one. |
| Device family | `TARGETED_DEVICE_FAMILY: "1"` — iPhone only. Xcode's default of `1,2` was silently claiming iPad support, which would have demanded iPad screenshots and put this portrait-only phone UI in front of a reviewer on an iPad. |

**Review blockers are cleared too** — by narrowing v1's scope rather than finishing every feature. See `docs/APP-REVIEW-NOTES.md` for the App Store Connect text.

### v1 ships narrower than the codebase

Two flags in `Core/Services/AppFeatures.swift` gate what's reachable. **Nothing was deleted** — restoring a feature is flipping its flag plus the follow-up work its doc comment lists.

| Flag | v1 | Why |
|---|---|---|
| `paymentsEnabled` | `false` | The Stripe rail is built and test-verified, but shipping it needs live keys, a demo account with a seeded `paid` booking (a reviewer can't complete a charge), an IAP justification, and — the real blocker — curated `PostBooking` content for **every** reservable retreat, which only Mallorca has. The retreat CTA becomes **"Request a place"**, opening a support email via `LegalLinks.enquiry(about:)`. |
| `circleTabEnabled` | `false` | The tab's whole content was "lands here next" — Guideline 4.2. `MainTab` omits the case; `BottomNav` builds from `allCases`, so it disappears on its own. `CommunityPlaceholder` is parked, not deleted. |

### Practice media is data-gated, not code-gated

`PracticeViewModel` has **no mock fallback** — the old one served public sample media (Big Buck Bunny, a stock MP3), which shipped is a Guideline 2.1 rejection. All sample URLs are gone from `Models.swift`; the `.mock` arrays are preview fixtures with empty `storagePath`, and `Massage.media` is now **optional** so the player only appears with real media.

`PracticeView` asks `SupabaseService.availablePracticeCategories()` which of Somatic / Breathwork / Meditation have rows. Unseeded tracks render dimmed with a `SOON` badge, aren't tappable, and the header copy drops its "listen or watch" promise. **Seeding `practice_sessions` lights them up with no app release.** Apply `0005_practice_sessions.sql` (table + RLS + the `practice-media` bucket + seeding instructions), upload media, insert rows.

### Quality pass (Gate 3)

- **No `print()` anywhere.** `Core/Utils/Log.swift` wraps `os.Logger` with four categories (`auth`/`data`/`media`/`payment`). Chosen over `#if DEBUG print` because interpolation is **redacted by default in Release** — an error carrying a token or email doesn't leak. Mark anything safe to read with `\(value, privacy: .public)`.
- **Home no longer invents state.** "Continue your journey" (a hardcoded "DAY 3 OF 7" for a program nobody is enrolled in) and "Circles meeting now" (live community activity, for a tab that's cut) are **gone**. The programs shelf is data-gated like Practice — hidden until `programs` has rows (`0006_programs.sql`), no mock fallback, and informational only since there's no program detail screen.
- **Mood chips do something.** Each `MoodChip` carries `suggests` / `ritual` / `ritualLead`. Selecting one rewrites the ritual card and "Begin now" **switches to the Practice tab and opens that section** — routed through `MainTabView.pendingPractice`, which `PracticeRoot` consumes on appear. Every mood points at a section with real content (journal / exercises / recipes / massages), never at a "Coming soon" track.
- **Offline is visible.** `ConnectionBanner` renders above the tab content whenever `AuthManager.needsRetry`, with a working Retry. A failed launch-time sign-in used to be completely silent.
- **The webhook race is closed.** `reserve(userID:)` no longer trusts the client: on PaymentSheet success it enters `.confirming` and polls `fetchBooking` (~9s, backing off) for the row the webhook writes. Previously a slow webhook left a **charged** customer seeing "Reserve" again on next launch.
- **Double-charge and overselling are blocked server-side**, in `create-payment-intent` where they belong — a paid booking for the same `(user_id, retreat_id)` returns `409 already_booked`, and paid bookings at or over `max_guests` return `409 sold_out`. The capacity check is not airtight against two simultaneous final-seat checkouts; closing that needs a transactional hold.
- **Accessibility** labels added to the mood chips, ritual card, retreat cards, both Reserve controls and the checkout pay bar.

### Other v1 changes

- **`fetchRetreats()` filters `end_date >= today`.** The catalog was selling four retreats that had already finished. This originally hid **Mallorca** too — the only retreat with curated brochure + post-purchase content — which `0007_mallorca_dates.sql` fixed by moving it to 2027-07-21→26. `RetreatExperience.mallorca.dateRange` hardcodes "July 21–26" as brochure copy and **takes precedence on the detail screen**, so those two must be changed together.
- **Legal links** live in `Core/Services/LegalLinks.swift` — three `TODO` URLs that **must be replaced before submitting**. Surfaced as a Privacy · Terms · Support row in the You tab, and the checkout fineprint now links the terms it names.
- **DEBUG launch args** (all compiled out of Release, alongside `-uitest-*`): `-tab <name>` opens straight to a tab, `-mood <id>` preselects a mood chip, `-preview-retreat` renders the retreat detail in isolation, `-preview-confirm-email` opens `AccountView` on the confirm-your-email panel.
- **`group_chat_url` placeholder removed.** `Retreat.mock` carried `chat.whatsapp.com/REPLACE-WITH-MALLORCA-INVITE`; the offline fallback would have opened a dead link. Real invites come from the DB column.

## Current State

- **Implemented:** anonymous Supabase auth on launch; **just-in-time account gating** (`AccountGate`) — browsing is free, the account sheet is raised at the first practice and replays the interrupted tap, with **Sign in with Apple** (native button → `signInWithIdToken`) alongside email/password; **email/password accounts (Phase 1)** — create-account upgrades the anonymous guest in place, sign-in/sign-out, **account deletion** (`delete-account` Edge Function → re-anon; App Store 5.1.1(v) compliant), email-confirmation deep linking, `profiles` table with RLS + sync (You tab → `AccountView`); Welcome flow; Onboarding (4 questions + finish); Home dashboard; Retreats stack + detail; full Practice tab (category/menu landing → list → detail/player for the 3 media tracks plus Journal Prompts, Exercises, Food Recipes, Personal Massages; media plays via `PracticePlayerView`); **server-side practice history** — every practice opened is recorded to `practice_plays`, driving resume, completion state, the Home Continue card and streak, and the creator-payout report.
- **Retreat payments (Phase 2) — BUILT BUT OFF IN v1** (`AppFeatures.paymentsEnabled = false`; the CTA is "Request a place" → support email). Everything below is intact and returns when the flag flips. Stripe is wired end-to-end and **deployed + verified working in Stripe test mode** — `RetreatDetailView` Reserve → `create-payment-intent` Edge Function → Stripe `PaymentSheet` → `stripe-webhook` writes `bookings`. Reserve requires `auth.hasAccount` (else presents `AccountView`); Reserve now pushes a **checkout review** (`RetreatCheckoutView`) before the PaymentSheet, and an existing paid booking flips the CTA to "View your experience". Both Edge Functions are deployed, function secrets are set, and the Stripe webhook endpoint is configured. Going to **live mode** still needs live Stripe keys + a live webhook endpoint/secret (see `supabase/functions/README.md`).
- **Post-purchase experience (Mallorca) — unreachable in v1** (payments off; also gated on Mallorca being the only retreat with `PostBooking` content — its date is no longer a blocker, see `0007_mallorca_dates.sql`). Once reserved, `RetreatDetailView` → `RetreatCheckoutView` (review → Stripe) → `RetreatExperienceHubView` (welcome hub) → to-do's, packing, 1:1 guide booking, and a **mocked** concierge chat. State (to-do/packing checks, 1:1 bookings) is device-local via `RetreatTripStore`; content is curated in `RetreatExperience.PostBooking` (Mallorca only). Built in a **warm-espresso palette** (`RetreatPalette` — terracotta/olive/gold on espresso, all-Geist), the UX team's retreat-specific dark direction (distinct from the app-wide `Theme`); the matching `design-system/screens/` mirror cards carry the same inline `.mb` palette, and the original brochure-light cards are preserved in `docs/design-brochure-backup/`. The group-chat tile links an external **WhatsApp** group (`retreats.group_chat_url`). Future work parked: `docs/PLAN-deposit-installments.md` (deposit + 2 installments) and `docs/PLAN-group-chat.md` (native in-app chat, currently WhatsApp).
- **Backend wiring:** `SupabaseService` (actor + caching) is live. `retreats` is fetched from Supabase by both `HomeViewModel` and `RetreatsViewModel`; `programs` by `HomeViewModel`. `practice_sessions` is fetched per category by `PracticeViewModel` with **no fallback** — an unseeded table yields an empty track that `PracticeView` renders as "Coming soon" (via `availablePracticeCategories()`). `profiles` is read/written via `fetchProfile`/`upsertProfile`; `bookings` is read via `fetchBooking`; practice history is written via `recordPracticePlay` and read via `fetchPracticeProgress` (all uncached, RLS-protected).
- **Mock-driven:** `CommunityCircle` on Home; all Journal / Exercise / Recipe / Massage *content* (driven by `.all` arrays in `Models.swift`, pending their own tables — 5 prompts, 3 exercises, 3 recipes, 3 massages). Their **progress** is real and server-backed even though the content isn't. `JournalDetailView` stores reflections device-locally only, namespaced per member by `LocalUserStore`.
- **Parked (cut from v1):** Circle tab (Community) — `CommunityPlaceholder` / `TabPlaceholder` still exist but nothing routes to them. The You tab (Profile) is now partly real (account UI + status + the Privacy · Terms · Support row); its "Reset onboarding" button is gated behind `#if DEBUG`. Its guest branch ("Create account" / "Sign in") is unreachable while the account gate holds, but is kept as the correct fallback.
- **Deliberately not built:** Google sign-in. It was implemented (Supabase hosted OAuth in an `ASWebAuthenticationSession`) and removed on 2026-09-03 — Apple is the only third-party provider. Re-adding it means a Google Cloud OAuth client, the Supabase Google provider, and a second button in `AccountView`; prefer the native GoogleSignIn SDK over the web flow if it ever comes back.
- **Not yet built (next phases):** a bookings list/history UI (data exists in `bookings`); refund handling; **membership** subscription (a "mix" of digital + real-world perks → must use StoreKit IAP, not Stripe).
- **Tests:** one UI-test target (`SoulfullUITests/AccountGateTests.swift`, 2 tests) covering the account gate; no unit tests yet. The `-uitest-reset` / `-uitest-onboarded` / `-tab` launch hooks are what make it deterministic.
- **Offline fallbacks:** `retreats` (Home + stack) still falls back to `Retreat.mock` when Supabase returns nothing. **`practice_sessions` no longer falls back at all** — see the Practice note above. The Supabase project (`qkepgohdosmzebdmsctn.supabase.co`, "Soulfull iOS") is **ACTIVE_HEALTHY**.
- **Live backend state, verified 2026-09-06:**
  | Table | State |
  |---|---|
  | `retreats` | 7 rows; **4 upcoming** — Dolomites (2026-09-08), Lapland (2027-01-10), Chamonix (2027-02-02), **Mallorca (2027-07-21)**. Kyoto, Sedona and Bali have finished and are correctly hidden. Every `group_chat_url` is still `null`. |
  | `profiles` / `bookings` | Exist, RLS-protected; `profiles` holds real test accounts. |
  | `programs` | **Table exists, zero rows** (0006 applied). Home's Digital Retreats shelf hides itself. |
  | `practice_sessions` | **Table exists, zero rows** (0005 applied). All three media tracks read "Coming soon" — seeding lights them up with no app release. |
  | `practice_plays` + the `practice_progress` / `practice_creator_earnings` views | **Live** (0008 applied 2026-09-06), zero rows. Recording starts with the next practice opened on a build carrying this code. |
  > This corrects an earlier note claiming `programs`/`practice_sessions` return 404. They were applied; they were never seeded — a different problem with a different fix (upload media + insert rows, no migration needed).
- **Retention loop (new).** Home shows a **Continue** card for the most recently unfinished practice and a streak line once it reaches two days; session rows show a resume hairline or a completion seal. All of it is driven by real server-side history — nothing is invented, and with no history every one of these elements is simply absent. Requires `0008_practice_progress.sql`.

## Resources

Geist fonts live in `Resources/Fonts/` at the **repo root** (not inside `SoulfullGatherings/`) and must be listed in `Info.plist` `UIAppFonts` (currently the six shipped Geist weights). Images live in the asset catalog at `SoulfullGatherings/Assets.xcassets` and are referenced by string name (e.g. `"retreat-mallorca"`, `"home-bg"`, `"soulfull-logo-white"`); the same handful of retreat photos currently double as placeholder art across Practice content.