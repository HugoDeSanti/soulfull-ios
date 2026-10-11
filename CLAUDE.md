# Soulfull Gatherings — iOS App

SwiftUI iOS app for a wellness retreat and community platform. Dark, editorial aesthetic. Backend is Supabase (Postgres + Storage + Auth — Sign in with Apple or email/password). Browsing is open to an anonymous guest; an account is asked for only when someone reaches for something personal (see *Account gate*).

**iOS 18 minimum, Swift 6.0 (pinned in `project.yml`).** Always use current idioms — `@Observable` (not `ObservableObject`), `@Environment(Type.self)` (not `@EnvironmentObject`), `@State` (not `@StateObject`/`@ObservedObject`), typed throws, `NavigationStack` with typed `Route` enums. No compatibility shims — there is no older OS to support.

## Build & Run

[XcodeGen](https://github.com/yonaskolb/XcodeGen): `project.yml` is the single source of truth (target, Swift 6, iOS 18, bundle ID `com.soulfullgatherings.app`, the Supabase SPM package, Geist fonts, entitlements, `Secrets.xcconfig` injection). Run `xcodegen generate` after editing `project.yml` **or adding any file** — targets use explicit file references.

```bash
xcodegen generate
open SoulfullGatherings.xcodeproj   # ⌘R — iPhone only, portrait only
```

- `SoulfullGatherings/Info.plist` and `SoulfullGatherings.entitlements` are **generated and gitignored** — hand edits are silently reverted. Change keys and entitlements in `project.yml` (`info.properties` / `entitlements.properties`).
- Dark mode is forced at the `WindowGroup` with `.preferredColorScheme(.dark)`.
- The build only sources `SoulfullGatherings/` and `Resources/Fonts` (Geist, at the **repo root**, listed in `UIAppFonts`). `supabase/`, `docs/` and `design-system/` are not part of it.

## Architecture

**MVVM.** Each stateful screen has a ViewModel declared `@Observable @MainActor final class`. The app singletons `AppState`, `AppSettings` and `AuthManager` are the same, injected from `@main` and read with `@Environment(Type.self)`.

### Navigation (three tiers)
1. **Stage** — `AppState.stage` (`loading → welcome → onboarding → main`) drives the switch in `RootView`, animated. The onboarded flag is persisted as `sg.hasOnboarded` via `AppSettings`.
2. **Tab** — `MainTabView` hosts six `MainTab`s: `home`, `gatherings`, `programs`, `practice`, `community`, `you` (bar labels: Home · Gatherings · Digital Retreats · Practice · Community · You). `BottomNav` is a flat, docked, **deliberately static** bar with no lens, bounce or press animation (the owner found the springy glass capsule childish). Its You item is the member's `AvatarView`. `NavBarLayout` sizes each slot to its label plus an equal share of the spare, because six equal slots can't fit "Digital Retreats".
   - **Each tab lives in its own `UIHostingController` inside `TabPager`** (a small `UIViewControllerRepresentable` in `MainTabView`), made on first selection and kept, with only the selected one in the window. So a tab keeps its view models, scroll position and pushed screens while another is showing, costs nothing while hidden, and its `.task`s run again when it comes back. `MainTabView.page(_:)` hands each one the app's objects, dark mode, the tint and `scenePhase` explicitly, because a hosting controller starts a fresh environment: **anything new a tab reads from above must be forwarded there.** **Not a system `TabView`:** past five tabs, iPhone moves the rest into a "More" navigation controller, which put a stray back button (and a system list of tabs behind it) on Community and You. **Don't go back to a `switch` either:** rebuilding the tab on every tap flashed its empty state ("New gatherings are on their way") before the data arrived. Since a load now re-runs over data already on screen, it must not swap that data for a spinner or reset the focus, and an empty state needs a `hasLoaded`-style flag: empty only counts once a load has answered.
3. **Item** — Gatherings, Digital Retreats, Practice and Community each wrap a private `NavigationStack` root (`GatheringsRoot`, `ProgramsRoot`, `PracticeRoot`, `CommunityRoot`) with a typed `Route` enum and `@State path: [Route]`. Home and You have no stack. Value-based navigation is what makes swipe-back work.
   - `GatheringsRoot.Route`: retreat detail and the post-purchase screens, over `RetreatsStackView(isTabRoot: true)`.
   - `ProgramsRoot.Route`: program detail, a day **by day number** (not a `ProgramDay` value: the curriculum can be edited while a member is on it, and a stale copy in the path would keep rendering), and the journal/movement/recipe details.
   - `PracticeRoot.Route`: session list, journal/movement/recipe lists and details, `instructor(id, from:)`.
   - `CommunityRoot.Route`: `friends`, `notifications`.
   - Cross-tab hand-offs go through `pendingPractice` / `pendingProgram` / `pendingRetreat`, and **replace** the target tab's path, which may still hold a screen from an earlier visit. ⚠️ **`pendingRetreat` is consumed once the stack's catalog has loaded, not on appear.** Pushing in the same update the tab appears pinned the CPU at 100% (`GatheringsTabTests` catches it).

**"Programs" are called "Digital Retreats" everywhere a member can see them** (labels, headings, VoiceOver). The code, the tables and the `-tab programs` launch arg keep "program". Write new copy as "digital retreat".

**Guides (instructors) appear only on the pages of what they made:** a "Your guide" `GuideCard` on every practice page and digital retreat, and a face chip in the session player. They **never** appear on the Practice landing (a shelf there was removed at the owner's request). Cards open the profile through the `openInstructor` environment action that `PracticeRoot` and `ProgramsRoot` install, and sheets inherit it. `from` is the back label. A guide who is already on top isn't pushed again.

### Auth
`AppState.initializeAuth()` (from the app's `.task`) calls `AuthManager.initialize()`, which applies the session stored on the device (no network), then confirms it with the server or opens an **anonymous** session so catalog reads work, and routes on `hasOnboarded` alone.

- **The launch logo never waits on the network for more than `AppState.launchGrace` (2s, `LaunchHold`).** The route doesn't depend on the check, so the check finishes behind the app. It used to sit out URLSession's 60s timeout on a stalled connection.
- **Anything that replaces the session (sign-in, create, confirm, the deep link, sign-out) first awaits a check still in flight** (`settleSessionCheck`). Otherwise a late refresh or anonymous sign-in overwrites the new session in the Keychain, and a late failure sets `.failed` over a healthy one.

- **Only a session that is really gone becomes a guest** (`SessionRestoreDecision`): no stored session, or GoTrue rejecting the refresh token. Offline, timeouts, 5xx and the like keep the stored session and set `.failed(ConnectionFailure)` (`.offline` / `.unreachable`); the banner's Retry, or coming back to the foreground, runs `retry()` (which keeps `state` at `.failed` and flags `isRetrying` while it tries). Falling back to a guest on any error once overwrote a member's Keychain session after a network blip at launch, and wiped their stores.

- **Identity:** `State` (`initializing` / `authenticated` / `failed`), `isAnonymous`, `hasAccount` (authenticated **and** not anonymous), `email`, `userID`. **Gate account-only flows on `hasAccount`, never `isAuthenticated`**, because a guest is authenticated too.
- **Guests are disposable.** A guest is an anonymous auth user with **no `profiles` row**, and the nightly pg_cron job `purge-idle-guests` deletes one idle for 30 days (0023). A purged guest's next launch just gets a new guest, because the SDK reports the session missing and `initialize()` falls back to `signInAnonymously()`. So never give a guest server state that has to survive. A second job, `purge-stale-auth-flows` (0025), deletes `auth.flow_state` rows older than 7 days: confirmations left behind by the code path, another device, a deleted account or nobody.
- **Email/password:** `createAccount` upgrades the guest in place (`auth.update`, same user id, data carries over) and falls back to `signUp` without an anonymous session. `signOut` re-opens a fresh anonymous session. `AuthManager.pushOnboardingAnswers` is the only code that writes the device's answers to `profiles`: it pushes on create (and from `finishOnboarding` for a member), hydrates on sign-in, does nothing when the device has no answers (it would blank the row), and `mergeProfile` handles Apple sign-in, which can't tell a new account from a returning one.
- **Welcome's "I already have an account" offers sign-in** (`AccountView(mode: .signIn)`, closable, never a gate); `AppState.returnFromWelcomeSignIn()` goes straight to main when the profile has a name, to onboarding when it doesn't, and stays on Welcome when the sheet was closed.
- **Sign in with Apple is the only third-party provider.** Google was built and then removed, so there is no GoogleSignIn and no web-auth flow. `signInWithApple` calls `signInWithIdToken`, which *replaces* the guest instead of upgrading it.
- **Email confirmation has three completion paths. Don't reduce it to the deep link:** the PKCE verifier lives in this iPhone's Keychain, and `soulfull://` doesn't open on a laptop.
  1. Same device: `soulfull://auth-callback` → `.onOpenURL` → `AuthManager.handleDeepLink` (PKCE `session(from:)`).
  2. Any device: the emailed numeric code → `confirmEmail(code:email:)` (`verifyOTP`). The server sets the code length (6 today); never hardcode it.
  3. Confirmed elsewhere: `refreshConfirmationState()` re-reads `GET /user`. It is polled by `beginConfirmationWatch`, which `AuthManager` owns so the watch survives the sheet closing (backs off from 5s to 60s), and it runs once at launch for a guest.
  The guest upgrade is an email **change**, so most people get the *Change Email Address* template, not *Confirm signup*. Both are branded in `supabase/templates/`.
- **"Forgot password?"** (sign-in mode only) opens a two-step panel in the same sheet: an address → `requestPasswordReset` (`resetPasswordForEmail`), then the emailed code **plus** the new password → `verifyPasswordResetCode` (`verifyOTP(type: .recovery)`, a sign-in like `signIn`, so the profile is hydrated) → `setNewPassword` (`auth.update`).
  - **The recovery email is code only, with no link** (`supabase/templates/reset-password.html`). A recovery link has no "confirmed elsewhere" path: opened on a laptop or prefetched by a mail scanner it spends the token, and the code in the same email dies with it. So there is no recovery deep link and no extra redirect URL.
  - **The code is spent once** (`resetCodeAccepted`). A password refused after an accepted code is retried without the code, because they're already signed in; the sheet's auto-dismiss on `hasAccount` stands aside until the password is set. GoTrue's `same_password` counts as done.
  - **Never say whether the address has an account.** GoTrue answers `/recover` with 200 either way, and the panel reads "If there's an account for…".

**Apple token revocation (Guideline 5.1.1(v)). Don't unpick this.** Deleting an account must call Apple's `/auth/revoke`. That needs a refresh token, and the refresh token comes from a single-use authorization code that expires in about 5 minutes, so it has to be captured at sign-in:
- **At sign-in:** `AppleSignInButton` puts `authorizationCode` into `AppleCredential` (don't drop it from the struct) → `AuthManager.storeAppleRefreshToken` → the `store-apple-token` Edge Function → `apple_credentials`.
- **At deletion:** `delete-account` reads the token *before* deleting the user, then revokes.
- **Both steps are best-effort by design.** A failed exchange must not cost someone their sign-in, and a failed revoke must not block their deletion. Apple issues a fresh code on every sign-in, so a miss fixes itself next time.

Setup and the end-to-end check are in `supabase/functions/README.md`.

### Account gate (just-in-time)
Browsing is free. The account is asked for at the moment someone reaches for something personal. `Features/Auth/AccountGate.swift` holds **only the pending action** and is not `@Observable`. `require(signedIn:_:)` returns `Bool`, and the caller raises `AccountView` from a plain `@State` Bool. On dismiss, `resume(signedIn:)` **replays the interrupted tap** if an account now exists.

| Open to a guest | Gated on `auth.hasAccount` |
|---|---|
| Home, the retreat catalog and detail, every Practice list, browsing digital retreats | Playing a session; journal / movement / recipe detail; joining a program |
| Community feed (All); **Report** a member (safety isn't gated) | The Friends scope and screen; liking; **Block** (a block must outlive the session, and a guest is disposable) |
| Instructor profiles, "Your guide" cards | Follow (the replay *sets* the state and never toggles it: `InstructorProfileViewModel.setFollowing`) |
| | The retreat application ("Request a place") |

There is one gate and one sheet, both in `MainTabView`, handed down as `requireAccount: (@escaping () -> Void) -> Void` (default `{ $0() }` for previews). **The `@escaping` inside the function type is required.** Without it the closure can't be stored and the build fails.

**Never gate browsing.** A registration wall at the end of onboarding was built and removed the same day because it fell under **Guideline 5.1.1(i)** (registration can't be required for core functionality). Don't add a gate in `AppState.initializeAuth()`, in onboarding, or on a whole tab.

## Code map

This lists only what the file names don't make obvious. Features follow `Features/<Area>/<Screen>View.swift` + `…ViewModel.swift`.

```
Config/Secrets.xcconfig(.example)  # Gitignored: Supabase host + anon key + DEVELOPMENT_TEAM. Copy the example on a new machine
supabase/                          # Backend as code; not in the Xcode build
├── migrations/                    # 0010–0028 (0001–0009 removed: `git show d20e3f6:supabase/migrations/`)
├── functions/                     # Deno Edge Functions (deploy + secrets: functions/README.md):
│                                  #   create-payment-intent, stripe-webhook (--no-verify-jwt) — Stripe, v1-dormant
│                                  #   send-retreat-enquiry — Resend; the applicant's email comes from the JWT, never the body
│                                  #   delete-account — Stripe customer, Apple revoke, avatars/<id>/ (each best-effort), then the user
│                                  #   store-apple-token; send-like-push (--no-verify-jwt + x-webhook-secret; failures answered 200)
│                                  #   report-member — stores a member report (service role) + emails info@; a guest may report
├── templates/                     # Branded auth emails (see its README)
└── placeholder-media/             # Generated test sessions: seed.sql / remove.sql + the generators (see its README)
SoulfullTests/ · SoulfullUITests/  # See *Testing*
SoulfullGatherings/
├── SoulfullGatheringsApp.swift    # @main: environment, dark mode, auth .task, .onOpenURL. Renders nothing while hosting unit tests
├── PrivacyInfo.xcprivacy          # This app only (UserDefaults CA92.1 + collected data). Keep in sync with the ASC privacy answers
├── Assets.xcassets                # App chrome only (see *Assets*)
├── App/                           # AppState, AppSettings, AuthManager, RootView, MainTabView (+ the four stack roots and the
│                                  # AccountGate sheet), BottomNav (BottomNav.height = 56 for anything pinned above it),
│                                  # ConnectionBanner (offline / failed session, with a working Retry; `connectionBannerInset()`
│                                  # on every tab root AND pushed destination — an inset around the tab pager or a
│                                  # NavigationStack never reaches the screens inside — so it pushes them down, never over Back)
├── Core/
│   ├── Models/Models.swift        # Every domain model. `.mock` fixtures are for previews / DEBUG screens only
│   ├── DesignSystem/              # Theme, Components, Atmosphere, SoulGlass, Pressable, ShaderFX + Shaders.metal, PinchBrowse, Parallax,
│   │                              # PresenceBadge, CatalogImage, AvatarView (tone from a STABLE hash: hashValue is salted per launch)
│   ├── Services/                  # SupabaseService (actor), SupabaseConfig, RemoteImage, AppFeatures (v1 flags), LegalLinks,
│   │                              # LocalUserStore, and @Observable singletons: AppClock, PracticeProgressStore, ProgramStore (+ the pure
│   │                              # ProgramUnlockRule), WrittenPracticeStore, InstructorDirectory, PresenceStore,
│   │                              # PushRegistrar (+ the AppDelegate), ProgramNotifications
│   └── Utils/                     # Log (os.Logger), Haptics, ArtworkTones
└── Features/                      # Auth, Welcome, Onboarding, Home, Retreats (+ Enquiry/, PostPurchase/), Programs,
                                   # Instructors, Practice, Community, Profile (the You tab)
```

- **`Retreats/Enquiry/`** is the website's "Join a retreat" form, which is what "Request a place" opens in v1. `RetreatEnquiry` encodes straight into the `send-retreat-enquiry` body and carries **no email**: the server reads it from the JWT, and the app shows the field locked. The question strings exist in both `RetreatEnquiry.Question` and the Edge Function, so change both together.
- **`Retreats/PostPurchase/`** holds the reserved-retreat hub, to-do's, packing list and 1:1 guide booking, all unreachable in v1. These screens use their own warm-espresso `RetreatPalette`, not `Theme`. Their state is device-local (`RetreatTripStore`). Photos come from optional `post_booking` paths through `TripImage`, which shows the plain espresso ground when a path is missing and never borrows another retreat's photo.
- **`WrittenPracticeStore`** keeps the last library it read in Caches, so the pages open offline. `isAuthoritative` means the tables were read *this launch*, and only then does an absent practice count as gone.
- **`PushRegistrar`** registers a token only for a signed-in member, never a guest, and forgets the device on sign-out. It asks for permission once, from a card on the Community tab and never at launch. A tapped like opens Community → Notifications; a tapped program reminder opens that digital retreat (`openProgramRequested`, the same hand-off as Home's day card). Debug builds use the APNs sandbox and Release builds production.
- **`CommunityViewModel`** fetches the Friends feed server-side by friend ids. It does **not** filter the All feed, because a friend's last practice can be older than everyone's last hundred.
- **`MemberSafety`** (Guideline 1.2): a "⋯" `MemberSafetyMenu` beside every other member (feed, search, requests, friends, notifications) offers **Report** (`ReportMemberSheet` → `report-member`) and **Block** (confirmation, then `CommunityViewModel.block`, which takes them off every list at once and keeps them off — `hiddenMembers` — even from a read that answers after the block). One `.memberSafety(…)` host per screen owns the dialog and the sheet; a guest's Block from inside the Report sheet waits for the sheet to close, because the account sheet can't rise over it. You tab → **Blocked members** (`BlockedMembersView`, from `blocked_members()`). Runbook: `docs/MODERATION.md`.
- **`GuideDashboardViewModel`** (+ `GuideDashboardView`, the sheet, and `GuideSummaryCard`, the You-tab card) shows a guide their own numbers through `guide_dashboard()`. It exists only for a member the team has linked to a guide (`instructors.user_id`): for everyone else the function answers no row and the You tab shows nothing. `ProfileView` owns one and hands it to the sheet, so both show the same read. A reload keeps the figures on screen, and a read started for the previous person is discarded (`generation`). Month labels are formatted in **UTC** (`PayoutMonth`), because payout months are UTC months.
- **`AccountViewModel`** clears the password on success and never replays it. It shows generic auth errors, because GoTrue's own messages reveal which accounts exist, but `AuthFailureCopy` first tells apart offline, rate-limited (429) and our-end failures, which reveal nothing. The sheet reopens on the code panel while a confirmation is pending (`auth.confirmationToResume`: this launch's address, or the stored guest's `newEmail` sent within 24h). An Apple cancel is `.cancelled`, not an error.
- **`InstructorProfileViewModel.setFollowing`** is optimistic and reverted on failure. A version counter throws away a social read that started before a follow.

## Design system

The direction is **"still"** (owner's brief, 2026-10-10: the rounded, bouncy app read as playful; it should feel serious, with colours like the **Open** meditation app). It has four parts:
- **Photography and near-white.** Every screen's photograph stays visible behind it; colour comes from photography, never from the chrome.
- **Square.** Nothing is rounded.
- **Still motion.** Things fade in and settle at breath pace; nothing springs, bounces, squishes or zooms.
- **Space.** Empty space is part of the layout: hairline-ruled open sections rather than stacks of boxed cards, small tracked caps labels, and lighter headlines. The rhythm is `Theme.sectionGap` (64) between sections, ~20pt from a section's label to its content, and **12pt between cards that belong together** (Home's day / Continue / ritual cards stack under the moods as one section; spaced as sections, each floated alone, owner 2026-10-10).

The earlier "quiet luxury" pass (Liquid Glass, squish, zoom pushes, honey glows) is gone; don't bring its idioms back. All brand values are in `Theme.swift` (a static `enum`). **Never hardcode colors, font sizes or animation curves.

| Token | Usage |
|---|---|
| `Theme.bg` / `bgDeep` | True black canvas / the docked bar's ground |
| `Theme.surface` | Card fills |
| `Theme.ink` / `inkSoft` | Near-white primary / warm grey secondary text |
| `Theme.muted` | Tertiary text: **on black, glass or a card only** |
| `Theme.inkOnPhoto` | Body copy directly on a photo |
| `Theme.accent` / `accentSoft` | Moss (the logo's olive); `accentSoft` also marks "complete" and tints toggles |
| `Theme.ember` | Copper, the one warm mark: small text marks, counts, an unread dot, the liked heart. **Not** for selected surfaces, which use ink (an ink hairline or a 1pt underline) |
| `Theme.danger` | Muted brick for irreversible actions (Delete account) |
| `Theme.line` / `glassBorder` / `glassBorderHigh` / `hairline` (0.75) | Rules / surface strokes / stroke width |
| `Theme.gutter` (24) / `sectionGap` (64) | Page side margin / space between a page's sections |
| `Theme.Motion.press` / `release` / `settle` / `reveal` / `stage` / `breath` | The only animation curves: all eases. `settle` (0.6s) when a state changes, `reveal` (1.1s) when something arrives, `breath` (6s) is every idle loop's period |
| `Theme.headline(_:weight:)` / `body(_:weight:)` / `eyebrow(_:)` | Geist fonts. `Text.sgEyebrow()` applies font + tracking + uppercase + color |

- **Everything is Geist** (Thin to Bold). There is no serif and no SF Pro. Display headlines are Light or Regular with negative `kerning`; nothing larger than a button label is heavier than Medium. Body text and eyebrows use positive `tracking` (2–3).
- **Shape: no rounded corners.** Use `Rectangle()` for photos, cards, buttons, chips, bars and progress tracks. Sheets get `.presentationCornerRadius(0)`.
  - `Circle()` is only for faces (`AvatarView`, guide portraits), dots of 10pt or less, and the player's breath ring.
  - A number is a folio ("01"), never a numeral in a circle.
  - A check box is a square hairline box.
  - Surface strokes are `Theme.hairline`.
- **Grounds:** every tab and page sits on its own `PhotoBackdrop`, blurred and darkened, as before the still pass. **The photo must stay visible** (owner, 2026-10-10).
  - The redesign briefly replaced the photos with black `Atmosphere` washes and put a black wash over every card. Both read as a dark veil and were reverted the same day.
  - Don't add a deeper dim, a black layer or an opaque ground over a backdrop.
  - `Atmosphere` (`Core/DesignSystem/Atmosphere.swift`) survives only as Home's ritual card wash (ember, `intensity: 1, fillsScreen: false`).
  - The practice player keeps `AuroraBackground`.
- **Surfaces** always go through `SoulGlass` (`.soulGlass(in:)` / `.soulGlassCard()`): a light frost (`ultraThinMaterial`) with a hairline, square, the same on every OS. The photo shows through it; there is no black wash over the frost.
  - Liquid Glass (`glassEffect`) was dropped on purpose: its lensing and touch-bounce read as playful.
  - Prefer no surface at all: a hairline and space separate sections and rows (`SectionLabel` is a rule plus a caps label).
- **Touch:** every tappable surface is a `Button` styled with `SoulPressableStyle` (or wrapped in a `PressableCard`), which **dims** to 0.55 on touch-down with a soft haptic and fades back on release. It never scales. Don't put `onTapGesture` on cards. Back, close and view toggles are `GlyphButton`: a bare glyph in a 44pt square, with `arrow.left` for back and `xmark` for close.
- **Motion:**
  - Curves come only from `Theme.Motion`. No `.spring`, `.snappy`, `.bouncy`, `scaleEffect` for emphasis, `.symbolEffect(.bounce)`, `.scale`/`.move`/`.offset` transitions, or shimmer.
  - Transitions are `.opacity`, or the `editorialRise` focus-fade (blur + opacity, nothing travels) on pure-SwiftUI leaves.
  - Stage changes crossfade (`AnyTransition.soulStage`). `listReveal()` and scroll transitions change opacity only.
  - `.breathing` stays within a few percent of scale. `PulseModifier` is opacity-only and loops forever, so use it only for persistent live indicators.
  - The only shader left is the player's aurora (`ShaderFX`, Reduce Motion aware). Film grain, shimmer, the noise dissolve and the ripple were removed.
- **Navigation:** pushes are the plain system push (the zoom transitions were removed). Tab roots report pushes through a `navHidden` binding (one per tab, because every tab keeps its stack) so `BottomNav` hides instantly. Retreats and Practice pinch out into a catalog grid, always paired with a visible toggle button.
- **Nothing is ever laid over the status bar; content dissolves under it.** Every scrolling screen's `ScrollView` carries `.statusBarFade()` (`Components.swift`), a mask that turns the content transparent behind the clock once it has scrolled (over the first 36pt), eased back in over the status bar's last 22pt, so the clock sits on the page's own photo. **No band of any colour** (owner, 2026-10-10): a black band behind the clock was removed three times: always-on in `MainTabView` (2026-10-09), then scrolled-only and 40pt deeper, then only as deep as the status bar. Each read as a black bar across the photo. Apply it to the `ScrollView` itself, before the `PhotoBackdrop` background and any pinned overlay (both must stay unmasked). A screen with a pinned Back bar passes a later `fadeIn` and a `reach:` so content also clears the bar (the retreat and digital retreat pages). The mask has to cover everything the scroll view draws, including past its frame under the status bar and home indicator, or that content vanishes; it is sized from `safeAreaInsets.top` in a `GeometryReader` and `ignoresSafeArea()`. Placing it with `ignoresSafeArea` on a background inside the mask didn't reach the status bar. The recipe page keeps its own ground behind its pinned link, since the page under it is black.
- **Type over photography is one rule in three parts, used together:**
  1. `PhotoBackdrop` draws a `topScrim` (default 0.45 over 340pt). Pass `0` only for a screen with an empty top.
  2. Text blocks on a photo carry `.onPhoto()`.
  3. On a photo, eyebrows use `Theme.inkSoft` (never `muted`) and sublines use `Theme.inkOnPhoto` at `Theme.body(14)`. Type on glass or a card keeps `muted`/`inkSoft`.

  Put `.onPhoto()` on **text only**, never on a container holding a `TextField`, `TextEditor` or video (gotcha 1).

**Rendering gotchas that have bitten this codebase. Re-read them before adding effects:**
1. **Metal effects (`layerEffect`/`colorEffect`/`distortionEffect`, even disabled) or blur over UIKit-backed views** (`NavigationStack`, `TextField`, video) render a yellow ⃠ placeholder. `blur(0)` still attaches a filter. Keep shaders and blur on pure-SwiftUI leaves, and use `editorialPageSoft` or plain transitions around platform views.
2. **`visualEffect` offsets and scales escape ancestor clips.** Use scroll-driven image motion only on full-bleed surfaces. Cards animate as whole units (`listReveal`).
3. **`scaledToFill` grows layout, not just drawing,** and pushes siblings off-screen. Contain fill images in `Color.clear.overlay { … }.clipped()`, as `PhotoBackdrop` does.
4. **`GeometryReader` inside an `HStack` over-claims width.** Prefer leading-anchored `scaleEffect` fills.
5. **A view only answers taps where it draws something.** A framed `Image` responds on its glyph alone, and `glassEffect` added no tappable fill. So the old `CircleIconButton` was an 11pt target inside a 38pt circle, and a glass `PressableCard` ignored taps between its lines of text. `SoulGlass` adds `.contentShape(shape)`, and `GlyphButton` frames its glyph in a 44pt `contentShape`. **Any other tappable thing that draws less than its frame still needs its own `.contentShape(Rectangle())` and a 44pt target.** That covers a bare glyph, a word with an underline, or plain text with padding, which the still design uses a lot. When a button feels dead, check its accessibility frame (a UI test's `app.debugDescription`), not its visual frame.

## Design ↔ code sync (Claude Design mirror)

`design-system/` is an HTML/CSS mirror of the UI, pushed to a Claude Design project (projectId `76dcee6b-dc46-486b-abb7-a0c06852f1fb`) where the UX team edits it. `design-system/README.md` holds the Swift ↔ CSS token and component map.

1. **Code → mirror, in the same change.** Update the mirror whenever you change something design-relevant:
   - `Theme.swift` → `shared/tokens.css`
   - `Components`, `BottomNav`, `SoulGlass`, onboarding `OptionCard`, `PracticeShared` → `shared/app.css`
   - a screen's layout, copy or structure → its `screens/*.html` (a new screen gets a new `@dsCard`)

   Logic-only and backend-only changes are exempt.
2. **Mirror → Claude Design:** `/sync-design push`. It is incremental, pushing only the changed cards, because a blanket push overwrites the team's edits. It also writes to claude.ai, so pull and check first, and confirm before pushing. Never push unprompted. After a design change, remind the user that a push is needed.
3. **Claude Design → code:** `/sync-design pull`, review the diff, then port the changes through the token map.

## Backend (Supabase)

The project is `qkepgohdosmzebdmsctn.supabase.co` ("Soulfull iOS"). The Swift SDK comes through SPM (`@preconcurrency import Supabase`).

- **`SupabaseService`** is an actor singleton. Its `client` is `nonisolated`, so `AuthManager` can reach it without an actor hop. Catalog reads use 5-minute caches, and nothing invalidates them automatically, so call `invalidateCache()` on logout or an explicit refresh. Member data is never cached.
- **Credentials** flow from `Config/Secrets.xcconfig` → build settings → `Info.plist` (`SupabaseHost`, `SupabaseAnonKey`) → `SupabaseConfig`. They never appear in Swift source. `SUPABASE_HOST` is the bare host with no `https://`, because `//` starts a comment in xcconfig. Missing or placeholder values crash at launch with setup instructions, by design.
- **Adding a fetch:** add a private `Codable …Row` DTO in `SupabaseService.swift` with snake_case `CodingKeys` and a computed property that returns the model. Then add `func fetch…() async throws -> [T]`, cached if it's catalog data. Surface failures through `AppError`.

### Migrations
- **The live database is the authoritative schema.** Migrations 0001–0009 were removed from the repo after being applied; recover them with `git show d20e3f6:supabase/migrations/`. Every file in `supabase/migrations/` has been applied, and each file's header explains its design and how it was verified.
- A new migration goes in `supabase/migrations/` and is applied with `supabase db push`. If you apply it through the Management API instead (`POST /v1/projects/<ref>/database/query`), **backfill `supabase_migrations.schema_migrations` the same day** so `supabase migration list --linked` stays in step.
- Apply auth-email templates by PATCHing the four `mailer_*` fields on the project's auth config. **Never run `supabase config push`**: it resets every unspecified auth setting to the CLI defaults, which turns off anonymous sign-ins.
- **When probing a table, read the status code, not the body.**
  - `200 []`: the table exists and is either empty or filtered by RLS (member tables always look empty to the anon key).
  - `404`: the table is missing.
  - `000`: curl timed out, so retry.

### RLS and grants: gotchas that have bitten
- **Anonymous guests use the `authenticated` role, not `anon`.** `signInAnonymously()` issues a real JWT with `is_anonymous: true`. Catalog tables must therefore grant SELECT to **both** roles (`for select to anon, authenticated using (true)`); a policy written `to anon` returns nothing to anyone. Refuse guests explicitly on member writes.
- **Supabase grants ALL on a new view to `authenticated`, and an owner-rights view over one table can be updated through.** The first apply of 0015 let members rewrite anyone's avatar through `community_members`. Every `revoke` on an owner-rights view must name `authenticated`, then grant SELECT back.
- A `security_invoker` view (`practice_progress`, `member_notifications`) respects RLS. An owner-rights view bypasses RLS, so **its grants are its only protection.** `practice_creator_earnings` and `creator_pool_shares` are owner-rights on purpose (they add up plays across all members). **Never grant either to a client role.** A guide reads their own slice only through the `guide_dashboard()` function.
- Money and entitlement state is written only server-side (the service role, in Edge Functions). Clients read their own rows under RLS.

### Tables
**Catalog** (guests and members read published rows; no client writes):
- **`retreats`**
  - `image_url` (see *Retreat content*); `tone_top` / `tone_mid` / `tone_base` hex strings, read with `Color(hex:)`; a nullable `group_chat_url` (an https WhatsApp invite); `experience` jsonb (the brochure).
  - `fetchRetreats()` returns only retreats that **haven't started yet** (`start_date > today`), because a retreat nobody can join is a wrong date and price in front of a customer. `fetchRetreats(ids:)` has no date filter (the You tab's history).
- **`programs`**: slug id, nullable `date_range`, `days`, `curriculum` jsonb, `published`, `sort_order`, `instructor_id`. `fetchPrograms(ids:)` skips the `published` filter so a program that was taken down stays in a member's history.
- **`practice_sessions`**
  - `category` (`somatic` / `breathwork` / `meditation`), `media_kind`, `storage_path` (in the private `practice-media` bucket), `instructor_id`.
  - `program_only` hides a session from the Practice tab but not from a curriculum.
- **`journal_prompts` / `exercises` / `recipes`** (0021): the written libraries, read together by `fetchWrittenLibrary()` through `WrittenPracticeStore`.
  - **Ids are a contract**: the ledger, curricula and saved reflections all key on them. Never change or reuse an id; unpublish instead.
  - `recipes.angle` is a dietary angle, not `lead`.
  - Runbook: `docs/ADDING-A-WRITTEN-PRACTICE.md`.
- **`instructors`** (0019): rows written by the team, not member accounts.
  - `user_id` (a guide's own account) is hidden from clients by a **column grant**, so the app lists columns explicitly (`select *` fails with 42501).
  - A trigger keeps `lead` on sessions and programs equal to the guide's name.
  - **A guide linked to an account is named by that account** (0027): `instructors.name` is then a trigger-kept copy of `profiles.full_name`, renaming the member renames the guide, and a direct edit is reverted. A person can't have one name as a guide and another as a member.
  - Runbook: `docs/ADDING-AN-INSTRUCTOR.md`.
- **`creator_pools`** (0026): one row per UTC month (`month` is its first day), the month's pool for guides (15% of the app's revenue after costs, worked out and entered by the team), and `paid_at`. Written by the team in the SQL editor; **no client access** (RLS with zero policies, grants revoked). Runbook: `docs/CREATOR-PAYOUTS.md`.

**Member data** (owner RLS; guests refused on writes):
- **`profiles`**: one row per **member**, created by `handle_new_user` at sign-up, or when a guest's upgrade is confirmed (`is_anonymous` flips off). Guests have none and can't write one (0023).
  - The guest check is `caller_has_account()`, which reads `auth.users`, not the JWT claim, because the token still says anonymous just after confirmation, exactly when `pushOnboardingAnswers` writes.
  - Before 0024 every client upsert failed (42501): the email guard read `auth.users` as the client. Members from before 2026-09-30 have no answers on their row.
  - `upsertProfile` never writes `stripe_customer_id`, the timestamps, `avatar_url` or `share_activity`. The last two have their own targeted setters. It leaves out an **empty `full_name`**, so a push never blanks a name.
  - **The name lives here; `AppSettings.userName` is only the phone's copy** (Home's greeting, the You tab). It is reconciled at launch (`AuthManager.syncMemberName`), at sign-in and on the You tab. The profile's name wins. A row that lost its name gets it back from the phone, or else from the sign-up name (`MemberNameDecision`, written with `setProfileName`). Until 2026-10-11, onboarding committed the name it hadn't asked a member for, which pushed `full_name: ''` and greeted them as "Friend".
  - `avatar_url` is check-constrained to `avatars/<own id>/<uuid>.jpg`. Each upload is centre-cropped on the device to a 512px JPEG and gets a **fresh uuid**, because the path is every phone's cache key.
- **`practice_plays`** and the **`practice_progress`** view: see *Practice progress*.
- **`program_enrollments`**: `enrolled_at` is day 1's unlock and is set by the server clock.
- **`program_day_completions`**: **latched**, with no update policy, because the completion date is the next day's unlock.
- **`bookings`**: read-only for the owner and written by `stripe-webhook`. `user_id` is nullable, `on delete set null`.
- **`apple_credentials`**: **no client access at all** (RLS with zero policies *and* grants revoked). A 42501 response proves the table exists; a 404 would mean it's missing.
- **`device_tokens`**: APNs tokens. A trigger hands a token to whoever registered it last.

**Social:**
- **`community_members`** (owner-rights view): id, avatar, and a `display_name` shortened **in SQL** ("Hugo De Santiago" → "Hugo D."), so the full name never leaves the row. Permanent accounts only. `search_members(q)` searches by name, **never by email**.
  - **It leaves out anyone either side has blocked** (0028), per caller (`auth.uid()` in an owner-rights view reads the caller's JWT). The feed, presence and follower faces, `member_notifications` and the friendship/like insert policies all go through it, so that one filter covers them; `search_members` carries its own.
  - An objectionable name (`is_objectionable_name()`, whole words, EN + ES, plus "soulfull"/"admin") shows as "A member".
- **`community_activity`** (owner-rights view): finished plays only, **never journal prompts**, and only from members with `share_activity` on. It never exposes seconds played. Adds `like_count` / `liked_by_me`.
- **`friendships`**: one row per pair of members, in either order. Only the addressee can update a row, and only to `accepted`. Either side can delete it, which covers decline, withdraw and unfriend.
  - **A decline starts a 30-day cooldown** for that direction (0028): the addressee deleting a *pending* row is logged in `friend_request_declines`, and a new request inside 30 days raises `P0001 friend_request_cooldown`, which the app words as such (`Error.isFriendRequestCooldown`). Withdrawing starts none; the decliner can still ask the other way.
- **`member_blocks`** (0028): owner RLS, members only (`caller_has_account()`). A block's trigger ends the friendship/request and removes likes (and their notifications) both ways. The blocked member can never read it.
- **`member_reports`** (0028): **no client access**; written only by `report-member` with snapshots of what was reported. `status` open → actioned / dismissed by the team. **We promise review within 24 hours.**
- **Likes:** `practice_play_likes` → `notifications` → the `member_notifications` view.
  - Only the like trigger writes `notifications`. An unlike removes the notification if it's still unread, and only `read_at` can change.
  - Each new notification fires `send-like-push` through pg_net, with the URL and secret stored in Vault — except a **`silent`** one: the same person re-liking the same practice within 24 hours of the last push (`like_echoes`, 0028) still lands in the bell but doesn't buzz.
- **`instructor_follows`** + the **`instructor_social(id)`** RPC: followers, following, `followed_by_me`, `is_me`, and up to 3 faces (friends first, `share_activity` members only, never the caller).
- **`practice_presence()` / `program_presence()`** RPCs: see *Presence* under *Current state*.

### Required Auth dashboard settings (the app breaks silently without them)
1. **Anonymous sign-ins ON**, or launch lands in `State.failed` with no session.
2. **Confirm email** works either way. If it's ON, allow-list `soulfull://auth-callback` under URL Configuration. It must match `SupabaseService.authRedirectURL` and the `CFBundleURLTypes` scheme.
3. **Custom SMTP** with the sender name "Soulfull Gatherings". The built-in sender can't be renamed and is heavily rate-limited.
4. **Apple provider ON**, with `com.soulfullgatherings.app` in *Client IDs* and *Secret Key* left blank. An empty Client IDs list rejects every Apple sign-in, so verify it before shipping.

### Retreat content is self-serve (adding a retreat needs no release)
Runbook: `docs/ADDING-A-RETREAT.md`.
- **`image_url`** is routed by its shape through `ImageSource` → `CatalogImage`. If an image fails to load, it shows a quiet gradient, never a blank.
  - `https://…` is loaded directly.
  - `bucket/path.jpg` is a public Storage object (the first segment is the bucket).
  - A bare name is a bundled asset.
- **Retreat photos** live in the public `retreat-images` bucket, named `<place>-<yyyy>-<mm>.jpg`. Catalog photography is public on purpose. Private member media (`practice-media`) is served through signed URLs (`signedMediaURL`, valid for 1h).
- **Image caching:** Supabase serves public objects with `cache-control: no-cache` no matter what you upload them with, so `RemoteImageCache` caches **decoded** images instead of relying on `URLCache`.
- **The brochure** is the `retreats.experience` jsonb column.
  - ⚠️ **A malformed `experience` fails soft:** the error is logged and the retreat shows the short layout. When "the brochure isn't showing", check the log for a decode error first. `programs.curriculum` fails soft the same way.
  - A `date_range` field inside it is optional and normally left out. If present, it overrides the row's dates.

### Practice progress = creator payouts
Every practice opened is recorded to `practice_plays`. That table is the member's resume and streak history, and it is also **the record creator payouts are calculated from** (the `creator_pool_shares` view, 0026). Because both come from one ledger, they can never disagree.
- **The payout rule (owner's decision, 2026-10-07):** a guide earns on **time heard** and is paid a **share of a monthly pool**. The pool is **15% of the app's revenue after costs** (agreed 2026-10-07; costs include the fees Apple takes and cloud hosting, and the rest of the list is open). The share is their sessions' seconds heard that month over every guide's; earnings are pool × share, rounded down to the cent. Sessions only (the written libraries show reach on the dashboard but take no part), never a guide's own plays, UTC months. While a month runs, guides see an estimate from the share so far; **a month whose pool isn't set shows the share and no amount**. The payout run and the guide dashboard read the same view. Runbook: `docs/CREATOR-PAYOUTS.md`.
- **`practice_plays.instructor_id`** is the guide a play credits, **stamped by a server trigger** from the content row at insert and frozen after it. The client never sets it (its `creator` is a name it sends, so it can't be trusted with money). It has **no foreign key on purpose**: `on delete set null` is an UPDATE that the freeze would revert, and `restrict` would stop a guide being taken down. Rows from before 0026 were backfilled only where the session's guide matched the `creator` snapshot, with the integrity trigger off (it moves `updated_at`, which program days read).
- **Rows:** each row has a client-generated `client_event_id`, so a retried write can't pay a creator twice. `content_title` / `creator` / `category` are copies taken at the time. **There is no delete policy**, because deleting a play would erase a creator's earnings.
- **A DB trigger enforces integrity:**
  - The identity columns, `duration_seconds`, title and category are frozen.
  - `seconds_played` can only go up and is capped at the frozen duration.
  - `completed` latches.
  - **When you change the trigger, test the cap as well as `seconds_played`.** The cap was once client-writable, which made it useless.
- ⚠️ **`user_id` is frozen only when the new value isn't null.** `on delete set null` is itself an UPDATE, and a blanket freeze undid it. RLS (`with check (auth.uid() = user_id)`) stops a client from nulling its own row. As a result, deleting an account **anonymises** its plays rather than deleting them, because the creator still earned them.
- ⚠️ **Retiring a library once real rows use it:**
  - Keep the `PracticeContentKind` case and the `content_kind` constraint. An unknown kind decodes as `.session`, which would quietly credit another creator.
  - Drop only the `PracticeMenuItem` case, and make `PracticeProgress.menuItem` optional.
  - Migration 0012 shows the `count(*)` query that tells you whether real rows exist.
- **Measurement:**
  - **Media sessions:** `PlaybackReporter` counts *media* time, so seeking and pausing count for nothing, and it reports every 20s. A session **completes only when its end is reached with at least 80% actually heard** (`MediaTimeMeter.requiredShare`), counted across unfinished sittings.
  - **Written practices** count time on screen (`.practiceActivity(_:)`), in the foreground only and capped at 30 minutes per visit. A journal prompt completes once something is written; the others after 45s. Journal plays declare a nominal 900s duration so the server cap applies to them too.
  - **A written practice with media** passes `enabled: false` so a sitting isn't counted twice.
- **Client-reported seconds are capped, not proven.** Making payouts defensible against a determined cheat would need an Edge Function that cross-checks the Storage access logs.

### Digital programs (the Programs tab)
A program is free to join (behind the account gate), self-paced, and opens a day at a time. Its days live in the hand-authored `programs.curriculum` jsonb: `0014_seed_program_finding_ground.sql` is the complete worked example (activities are `{"kind", "content_id", "note"}`), and it fails soft like the brochure.
- **The unlock rule is the feature.** Day 1 opens on enrolment. Day N+1 opens when **every activity of day N is done _and_ the local date has moved past the day day N was finished on** (`startOfDay + 1 day`, not `+86400`).
  - The rule lives in `ProgramUnlockRule`.
  - `ProgramDayState` keeps `complete` / `open` / `opens(date)` / `awaitingPreviousDay` separate, because "come back tomorrow" and "not finished yet" call for different actions.
- ⚠️ **An activity counts toward a day only if it was completed after that day unlocked** (`lastPlayedAt >= dayUnlockedAt`). `practice_progress.completed` never resets, so without this rule a member's past practice would complete days the moment they enrol. The same practice on day 2 and day 6 has to be done twice, on purpose.
- **The device clock decides the date,** so winding it forward skips the wait. Accepted: this is a free program, not an exam.
- **Day completion is latched,** even though activity completion is not.
- **Programs record nothing of their own.** Activities open the same screens as the Practice tab and write `practice_plays` the same way, so a creator is paid identically either way. Leaving a program clears the enrolment and day rows and **touches no play history**.
- **Missing activities:**
  - An activity whose content doesn't exist is **dropped and logged**, because an activity that can't be opened would block the member forever.
  - A day with no activities left closes on its own.
  - ⚠️ **Missing is not the same as not loaded yet** (`ActivityLookup.pending`, `ProgramDayResolution`). If a library hasn't been read this launch, or a lookup failed, the activity is hidden but **the day stays open**. Completion is latched and can't be undone.
- **Program reminders are local notifications** (`ProgramNotifications`), sent at **08:00** on the morning a day opens (days open at midnight). Permission is asked at enrolment, never at launch. A day's pending reminder is cancelled the moment that day is completed. Push is used only for likes.
- **Yoga has no category of its own.** It is step content in Movement (`exercises`).

### Device-local private data (`LocalUserStore`)
Journal reflections and trip checklists stay on the phone. The privacy policy promises reflections never leave it.
- **Per-member namespace:** keys are `sg.u.<user id>.…`, never a flat key. A flat `sg.journal.<id>` once let two people on the same phone read each other's writing.
- **Storage:** reflections go through `privateText` / `setPrivateText`, which write a file under Application Support with `NSFileProtectionComplete`, excluded from backup. A plist would travel in iCloud and Finder backups and break the promise.
- **Lifecycle:** `AuthManager.apply(_:)` calls `adopt(userID:isAnonymous:)`, which hands a guest's data to the member they become. `deleteAccount()` calls `purgeCurrentScope()`.

### Payments (server-side only in v1)
- **The Stripe server side is deployed and tested in test mode:**
  - `create-payment-intent` reads the real price from `retreats`, keeps the Stripe customer on `profiles`, and refuses with `409 already_booked` / `409 sold_out`.
  - `stripe-webhook` writes `bookings` with the service role.
- **The client side was deleted** (`StripePaymentSheet`, `PaymentService`, the checkout view, `reserve()`). It pulled in a card scanner, which forced a camera permission prompt the app couldn't justify.
- **Why Stripe:** retreats are real-world services, so Stripe (not in-app purchase) is the right rail. A future membership would need StoreKit.
- **Restoring it:** the steps are in `AppFeatures.paymentsEnabled`'s doc comment, and the keys and permissions are in `supabase/functions/README.md`. If Stripe comes back, use `github.com/stripe/stripe-ios-spm`, not `stripe/stripe-ios`, whose multi-GB history makes package resolution crawl.

## Key conventions

- **Observation:** `@Observable @MainActor` on every ViewModel and app singleton. No `ObservableObject` / `@Published`.
- **Haptics on every interactive tap:**
  - `Haptics.tap()` for secondary actions, `.bump()` for primary CTAs, `.select()` for scroll and toggle changes, `.success()` for confirmations, `.prepare()` on gesture start.
  - `SoulPressableStyle` already fires `tap` on touch-down, so don't fire it twice.
- **Navigation** is value-based (typed `Route` enums), never `NavigationLink(destination:)`.
- **Onboarding** has 4 questions. The step machine has 5 cases because `finish` isn't a question. `canAdvance` is false whenever an answer is empty. **A member who signed in from Welcome starts at intentions (`asksName: false`)**: an account with no name is a Sign in with Apple that shared none, and asking for it after Apple is a rejection pattern. An unasked or blank name is never committed (`nameAnswer` is nil), so the phone's name is left alone.
- **Models** are value types, `Identifiable` + `Hashable` on `id`. Durations are stored in seconds (`durationSeconds`) with a `.durationLabel`.
- **Settings live in `AppSettings`** (UserDefaults with `didSet`, keys prefixed `sg.`), not `@AppStorage`.
  - Read and write `intentions` as the `Set`, never `intentionsRaw`.
  - `signOut()` and `deleteAccount()` call `clearPersonalAnswers()` (`hasOnboarded` survives). Without it, `mergeProfile` uploaded the previous member's answers to the next member's row.
- **Private device-local data goes through `LocalUserStore`**, never a flat `UserDefaults` key.
- **Practice history is server-side only** (`PracticeProgressStore` → `practice_plays`). Never make a local copy the source of truth.
- **No sample-data fallbacks, ever.**
  - A failed fetch shows a failure state that tells **offline** ("you'll need to be online") apart from **our fault** ("something went wrong at our end").
  - `Error.isOffline` counts only `notConnectedToInternet` / `networkConnectionLost` / `dataNotAllowed` / `internationalRoamingOff`. `timedOut` may be our backend.
  - A sample catalog shown as real is Guideline 2.1(a) temporary content. For the same reason, **never invent state**: no fake progress, no fake "present" counts.
- **Anything on screen that depends on the date reads `AppClock.shared.now`, never `Date.now`.** The app is mostly suspended, and SwiftUI only re-renders on observed changes; `SoulfullGatheringsApp` ticks the clock when the scene becomes active and at midnight / time-zone changes, which re-renders every view that read it (day unlocks, the greeting, the streak). Logic that takes time as an argument (`ProgramUnlockRule`, `PracticeStats`) is passed `AppClock.shared.now` by its live caller.
- **Media plays in a `.playback` audio session** (`PlaybackAudioSession` in `PracticePlayerView`), with the `audio` background mode in `project.yml` and lock-screen / Control Center controls (`AudioTransport`). Without it, sessions were silent with the ringer switch on silent and stopped when the phone locked. Media time keeps counting in the background, which is real listening.
- **Never force-refresh practice history as the player or a practice page closes.** `PracticeProgressStore.record` applies each write locally at once; a forced read that answers before the final write lands replaces that fresher copy (stale "N min left", a program day that doesn't close).
- **Remote images (`CatalogImage`) are keyed by URL** and read the decoded cache synchronously in `body`. A new URL in the same place (a changed profile photo) must never show the old picture, and a cached photo paints on its first frame. Seed the cache with an image the device made itself (`RemoteImageCache.insert`).
- **Tabs are rebuilt when a member becomes a guest** (sign-out, deletion: `MainTabView.shell`, keyed on `isAnonymous`), never on sign-in, because the account gate replays into the tab it came from.
- **No `print()`.** Use `Log` (`auth` / `data` / `media` / `payment`). Interpolated values are redacted in Release, so mark safe values `\(x, privacy: .public)`.
- **Account gating:** browsing never requires an account. Gate actions through `AccountGate`, on `auth.hasAccount`.
- **Tests:** behaviour changes ship with their tests (see *Testing*).

## Testing

There are two test targets in the `SoulfullGatherings` scheme, both scoped `[test]` so an archive never builds them.

| Layer | Where | Framework | What belongs there |
|---|---|---|---|
| Unit | `SoulfullTests/<Area>/…Tests.swift` (+ `Support/Fixtures.swift`) | Swift Testing | Business rules, state transitions, validation, data transformation, error handling. No network. |
| UI | `SoulfullUITests/…Tests.swift` | XCUITest | The critical journeys below, and nothing else. |

There is no integration target. A view model tested with an injected fake goes in `SoulfullTests`. What only exists live (RLS, decoding real rows, hit-testing) is what the UI journeys are for.

### Running
```bash
xcodegen generate   # after adding ANY test file
# Unit (~1 min including the build)
xcodebuild test -project SoulfullGatherings.xcodeproj -scheme SoulfullGatherings \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SoulfullTests
# UI (~8 min, against live Supabase), on a signed-out simulator
xcrun simctl create "Soulfull Tests" "iPhone 17 Pro"   # once
xcodebuild test -project SoulfullGatherings.xcodeproj -scheme SoulfullGatherings \
  -destination 'platform=iOS Simulator,name=Soulfull Tests' \
  -resultBundlePath build/ui.xcresult -only-testing:SoulfullUITests
# Narrow a run: -only-testing:SoulfullTests/PracticeStatsTests · -only-testing:SoulfullUITests/OnboardingTests
```
To get screenshots, run `xcrun xcresulttool export attachments --path build/ui.xcresult --output-path build/attach` and map the files through `manifest.json`.

**Get the environment right, or failures mean nothing:**
- Both targets need `Config/Secrets.xcconfig`, and UI tests need network.
- **Run UI tests on a simulator nobody is signed in on.** `-uitest-reset` resets `AppSettings` but not the Keychain session. With a member signed in, the guest tests fail and `RetreatEnquiryTests` sends a **real application email** to the team.
- Two runs on one simulator kill each other, so check `ps aux | grep xcodebuild` first.

### Unit tests
- **Setup:** `@testable import SoulfullGatherings`. The host app renders nothing while hosting unit tests (`isHostingUnitTests`).
- **Isolation:**
  - **Never touch** `SupabaseService.shared`, any `.shared` store, `UserDefaults.standard`, the Keychain, notifications or the real clock.
  - Inject dependencies through an init parameter whose default is the production value (`RetreatsViewModel(fetchRetreats:)`, `LocalUserStore(defaults:privateRoot:)`).
  - Move a rule that's tangled up with live state into a pure type next to its owner (`ProgramUnlockRule`, `MediaTimeMeter`). Don't widen `private` for a test.
- **Time is an argument** (`PracticeStats(_:calendar:now:)`, `ProgramUnlockRule.*(…, now:, calendar:)`).
  - Build dates with `Calendar.gregorian(in: "Europe/Madrid").at(2026, 9, 16, 12)`. Never use `Date()` or `Calendar.current` when the day matters.
  - Test daylight-saving edges with a named zone and date (São Paulo 2018-11-04 skips midnight; Madrid 2026-10-25 is 25 hours long).
- **Style:** one behaviour per test, and the name states the scenario and result. Separate arrange / act / assert with blank lines, use `@Test(arguments:)` for tables, and `await` rather than sleep.
- **Suites that guard the riskiest rules:**
  - `PracticeStatsTests`: streaks, classes, minutes, and the streak caption.
  - `ProgramUnlockRuleTests` and `ProgramDayResolutionTests`: day unlocks, and pending vs missing activities.
  - `MediaTimeMeterTests`: the payout measurement.
  - `LocalUserStoreTests`: per-member privacy.
  - `GuideDashboardTests`: UTC months, a month's money standing (estimate / no pool / due / paid), and the mapping of `guide_dashboard()`'s JSON.
  - `CommunitySafetyTests`: a block takes someone off every list and stays put against a late read, a refused block restores everything, the cooldown message, a report's shape; plus the Blocked members list.
  - `AccountGateReplayTests`, `PasswordResetFlowTests`, `RetreatEnquiryFormTests`, `WrittenPracticeStoreTests`, `ErrorClassificationTests`, and the instructor follow and library suites.

### UI journeys: the only ones that earn a UI test
| File | Journey |
|---|---|
| `OnboardingTests` | Splash → slides → 4 questions → Home greets by name; a relaunch skips it; "I already have an account" offers sign-in and can be closed |
| `AccountGateTests` | A guest opens a recipe → account sheet → the close button dismisses it |
| `PasswordResetTests` | Sign-in → Forgot password (the address carries over) → a code is sent → a wrong code is turned away → back to sign-in. Uses an address with no account, so nothing is emailed |
| `RetreatEnquiryTests` | Request a place → gate → form → Submit settles |
| `RetreatsStackTests` · `GatheringsTabTests` · `RetreatBrochureTests` | Catalog, detail, and the brochure (which fails soft); a tab keeps its place across a tab switch |
| `ProgramTests` | Catalog → days → Home hand-off → a guest can't join |
| `ProfileTests` | You-tab numbers and history against `-preview-you` |
| `CommunityTests` · `PresenceTests` | Feed, Friends, likes, the bell; presence lines (the 3-person minimum is SQL, verified live per 0018) |
| `MemberSafetyTests` | "⋯" → Report (needs a reason → sent → 24-hour promise → Block); Block asks, then their lines go; a guest can report but Block raises the gate; You → Blocked members → Unblock |
| `InstructorProfileTests` | The guide card on each page → profile → library hand-off; Follow; a guest's Follow → gate |
| `GuideDashboardTests` | A linked guide's You-tab card → the dashboard (estimate, months, paid to date, practices) → close; a month with no pool shows no amount; a member who isn't a guide sees no card |

- **Start from explicit state:** launch with `-uitest-reset`, usually plus `-uitest-onboarded` and `-tab <name>`, with fixtures from the DEBUG `-preview-*` args. No test may depend on another having run.
- **Selectors:** select by accessibility identifier wherever the label is copy. Grep `accessibilityIdentifier(` before renaming one.
- **Waiting:** wait for state (`waitForExistence`, or polls with a deadline), never `sleep`.
- **Assertions:** assert what a person would notice and attach a screenshot at each step. Mark new classes `@MainActor`.
- **When a control "doesn't work", reach for a UI test.** `app.debugDescription` shows the real hit frames.

### Policy
- For every behaviour change and bug fix, decide its testing impact and **say what you decided** in the report.
- **What a change needs:**
  - Logic, a state transition, validation, a data transformation or error handling changed → a unit test.
  - A journey above changed, or a new critical one appeared (spanning screens, crossing the gate or a system boundary) → a UI test **and an update to this table**. Keep its identifiers, launch args and fixtures working.
  - Copy-only or visual-only changes, docs, SQL and Edge Functions need no test. Verify SQL and Edge Functions live, per their READMEs.
- A reproducible defect gets a regression test that fails before the fix, where practical.
- **Before calling work done:** run `SoulfullTests` plus the UI tests for every journey touched. Run the whole UI suite when shared chrome changes (`RootView`, `MainTabView`, `BottomNav`, `AccountGate`, `AppState`, `SoulfullGatheringsApp`). Report what ran, the results, and any environment problem.
- **Never delete, skip or loosen a test to make a change pass.** If the product decision behind an assertion changed, change the assertion and say why in the commit.

## App Store (v1)

The submission checklist and the text for App Review are in `docs/APP-REVIEW-NOTES.md`. The build-level items (icon, launch screen, signing, privacy manifest, export compliance, push and Apple entitlements) are done. Rules to keep:
- **Launch screen:** use the `UILaunchScreen` dict + the `LaunchBackground` colour. Don't bring back `UILaunchStoryboardName`.
- **Devices and signing:** iPhone only (`TARGETED_DEVICE_FAMILY: "1"`). Archiving needs a real `DEVELOPMENT_TEAM` in `Secrets.xcconfig`.
- **Age rating: 13+** (owner's call, 2026-10-08). The new questionnaire is answered with user-generated content, health/wellness topics and social media **yes**, everything else none. The API computed 4+ from that, so `ageRatingOverrideV2 = THIRTEEN_PLUS` sets 13+, matching the Terms' minimum age and the public member feed; the legacy `appStoreAgeRating` reads it as 12+. Nothing in the app may mention alcohol, tobacco or drugs — check brochure copy before adding it (Guideline 2.3.6; the website's Chamonix page has a wine tasting).
- **Privacy answers:** `PrivacyInfo.xcprivacy` and the ASC App Privacy answers must list the same types (rewritten 2026-10-08: + phone, Instagram, other user content, contacts = friends, device ID = APNs token; − purchase history while payments are off). Onboarding answers are declared as `OtherDataTypes`, not Health. Revisit that if the questions become clinical.
- **Store listing** (description, keywords, screenshots, category Health & Fitness / Lifestyle, free, all territories but China mainland) was written through the ASC API on 2026-10-08; the source copy and screenshots aren't in the repo. Review notes: `docs/APP-REVIEW-NOTES.md`.
- **App icon:** only the "SOUL" block of the logo. The generator script: `git show d20e3f6:scripts/make-app-icon.swift`.
- **Demo account:** give the reviewer one, because no practice opens without an account.
- **Apple revocation** is deployed. The one unproven step is the real authorization-code exchange, which needs an Apple sign-in on a **physical device**.

**v1 ships less than the codebase contains.** The flags are in `Core/Services/AppFeatures.swift`:

| Flag | v1 | Notes |
|---|---|---|
| `paymentsEnabled` | `false` | The retreat button reads "Request a place" → `RetreatEnquiryView` → `send-retreat-enquiry` emails info@soulfullgatherings.com. Turning payments on is a checklist, not a one-line flip (see the flag's doc comment). |
| `depositInstallmentsEnabled` | `false` | Deposit + instalments exists only as brochure copy and is unbuilt (a parked design: `git show a755604:docs/PLAN-deposit-installments.md`); the server charges the full price. **Never put brochure copy on a pay button.** |

**Practice media appears only once data exists, with no code switch.** `PracticeViewModel` has no mock fallback, because shipping sample media is a Guideline 2.1 rejection. `availablePracticeCategories()` returns `.known(Set)` or `.unknown`:
- A track **known to be empty** is dimmed and marked "SOON".
- When the answer is **unknown** (offline), the track stays open, and the list's own error state and retry handle it.

**Legal links** are in `Core/Services/LegalLinks.swift`: privacy, terms and retreat policy on www.soulfullgatherings.com, plus the support email. They appear on the You tab and wherever a document is named. The live pages are the only copy of the text; the sources are recoverable with `git show d20e3f6:website/legal/`.

**DEBUG launch args** (compiled out of Release):
- **Navigation and state:** `-tab <name>`, `-mood <id>`, `-uitest-reset`, `-uitest-onboarded`.
- **Retreats:** `-preview-retreat`, `-preview-retreats`, `-preview-enquiry`.
- **Post-purchase screens:** `-preview-experience`, `-preview-todos`, `-preview-packing`, `-preview-guides`. These load a real retreat through `PreviewRetreat`.
- **Programs:** `-preview-programs`, `-preview-program`, `-preview-program-day`. `PreviewProgram` prefers a real program.
- **Social and profile:** `-preview-community`, `-preview-presence`, `-preview-you` (+ `-preview-you-today`).
- **Guides and auth:** `-preview-instructors` (+ `-preview-guest` to browse as a guest), `-preview-guide` (the guide dashboard; pair with `-preview-you`, + `-preview-guide-pending` for a month with no pool), `-preview-confirm-email`.

## Current state (2026-09-29)

**Built and live:**
- Guest browsing with just-in-time accounts (email/password and Apple), and account deletion.
- Welcome, Onboarding and Home (mood chips, ritual card, a Continue card, and a streak line from 2 days).
- Gatherings: the retreat catalog, brochure and application.
- Practice: three media tracks, plus journal / movement / recipes (now in the database).
- Server-side practice history, which drives resume, streaks and payouts.
- Digital Retreats: one live program, `finding-ground`.
- Community: feed, friends, likes, notifications and push. Report, Block and the friend-request cooldown (2026-10-08; 0028 applied and `report-member` deployed the same day).
- Presence counts, instructor profiles, and the You tab (stats and history).
- The guide dashboard (2026-10-07): people reached, past months' pool earnings and this month so far, for a member linked to a guide.

**Open items:**
- **No real guide sees a dashboard yet**, and no pool is set. The placeholder guide `alma-guerra` is linked to the owner's test account (hpdesanti+test@gmail.com, named "Hugo Santi", 2026-10-07), so it is now called "Hugo Santi" everywhere, and **every practice and digital retreat is credited to it** (the other four placeholder guides have empty libraries). That account's own plays don't count toward the guide, and the guide page shows it "This is your profile". Unlink with `update instructors set user_id = null where id = 'alma-guerra'`. Link a real guide (`docs/ADDING-AN-INSTRUCTOR.md` §4) and set a pool (`docs/CREATOR-PAYOUTS.md`).
- ⚠️ **The five live guides are PLACEHOLDERS**: invented people with AI-generated, unlicensed faces. **Remove or replace them before a build goes to App Review** (Guideline 2.1(a)); the steps are in `docs/ADDING-AN-INSTRUCTOR.md`. Some `PracticeSession.mock` leads (Michelle Campos, Analu Chavez, Valentina Velasco) are **real people**, so never take a guide's name from the mocks.
- **Push sends nothing** until key `5224W8727Y` has the APNs service ticked in the developer portal. Until then APNs answers `403 InvalidProviderToken`. No code change is needed afterwards.
- ⚠️ **`practice_sessions` holds three generated PLACEHOLDERS** (seeded 2026-09-30 so TestFlight testers can use the media tracks): an illustrated somatic video and two synthetic-voice audio sessions, now credited (like everything) to `alma-guerra` / "Hugo Santi". Their blurbs say "A placeholder while the real sessions are recorded". **Remove or replace them before App Review** (Guideline 2.1(a)): run `supabase/placeholder-media/remove.sql` and delete the three objects in `practice-media`. A track left with no rows goes back to "SOON" by itself. Test plays stay in `practice_plays` under that creator, so leave it out of payouts.
- **The post-purchase screens are unreachable** while payments are off, and only Mallorca has `PostBooking` content.
- **Not built yet:** a bookings history screen, refunds, and a membership (which would need StoreKit in-app purchase).
- **App Review demo accounts** (created 2026-10-08, confirmed, not linked to a guide): `appreview@soulfullgatherings.com` ("App Review") and its accepted friend `appreview.friend@soulfullgatherings.com` ("Demo Friend"), the demo enrolled in Finding Ground. The passwords are only in App Store Connect's review details. They have no practice history: none was invented.

**Product rules:**
- **Presence** ("75.7k present" + 3 faces):
  - A practice counts distinct members who **started** it in the last 24h. A program counts enrolled, unfinished members who were **active in the last 14 days**.
  - **Nothing is shown below 3 people** (enforced server-side). Faces show friends first. Journal prompts get a count but no faces. Opted-out members are counted but never shown.
  - **Never seed or pad these numbers.**
- **Community:** other members see exactly your id, "First L." name, photo, and the title, kind and time of your finished practices. They **never** see journal prompts, because reflections are private and a prompt's title gives away the subject. "Share my practice" (`profiles.share_activity`, on by default — the account sheet says so) removes you from the feed but leaves you findable. A profile without a `full_name` shows as "A member".
- **Safety:** Report and Block on every other member, a 30-day cooldown after a declined request, objectionable names hidden, and a 24-hour review promise (`docs/MODERATION.md`). The account sheet's agreement line points at the Terms' community standards.
- **You-tab stats** are defined in `PracticeStats` and nowhere else:
  - A *practice day* is a local calendar day on which any practice was **finished**.
  - A *class* is a finished session or Movement sitting (`countsAsClass`).
  - *Minutes* are time actually spent in those kinds, finished or not.
  - Home's "N days in a row" reads the same `streakDays`.
  - The streak caption tells *kept today* (finished something) apart from *practiced today* (only opened something).
  - In-person history is paid bookings for retreats that have ended, so it's empty for everyone while payments are off.
- **Health safety:** the Breathwork and Somatic lists open with a "Before you begin" `SafetyNoteCard` (`PracticeCategory.safetyNote`: seated or lying down / never driving or in water / stop if light-headed / not medical advice / pregnancy, heart, lung, seizure → doctor), and the player repeats it in one line (`safetyReminder`). Meditation needs none. Keep any new body-affecting track covered (Guideline 1.4.1).
- **No AI anywhere, and none planned.** A mocked concierge and a "Soul AI" welcome slide were removed. Don't bring back anything that advertises an AI: it misdescribes the app, and a real one would bring Guideline 1.2 obligations the app can't meet. "Assistant" appears only as a person's job title.
- **No Google sign-in.** It was removed on 2026-09-03. If it ever returns, prefer the native GoogleSignIn SDK.
- **Mood chips** on Home each point at a written section with real content, routed through `MainTabView.pendingPractice`.

## Assets

The asset catalog holds **app chrome only**:
- Four backdrops: `home-bg`, `welcome-bg`, `onb-bg`, `finish-bg`.
- Six `practice-*` category cards.
- `soulfull-logo-white`, the app icon, and the `LaunchBackground` colour.

**Nothing stored in Supabase is also bundled.** Content photography lives in Storage and loads through `CatalogImage`. The written practices borrow retreat photos as placeholder art, so offline they show their cached text over gradient placeholders. If that becomes a problem, the fix is giving Practice its own artwork, not bundling retreat photos again.
