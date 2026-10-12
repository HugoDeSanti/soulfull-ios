//
//  MainTabView.swift
//  Soulfull Gatherings
//
//  Hosts the primary tabs (Home, Gatherings, Digital Retreats, Practice,
//  Community, You) with a custom docked tab bar instead of the system one.
//  Gatherings is the retreats stack, pushing into Retreat Detail through its
//  own NavigationStack so native swipe-back works.
//
//  Each tab lives in its own hosting controller inside `TabPager`, so it keeps
//  its state — loaded data, scroll position, pushed screens — while another is
//  showing, exactly as a tab bar should. They used to be a `switch`, which tore
//  the old tab down and built the new one from blank view models on every tap:
//  the screen flashed its empty state ("New gatherings are on their way",
//  "Quiet for now") before its data arrived. Only the showing tab is in the
//  window, so a hidden one costs nothing and its `.task`s run again when it
//  comes back. Not a system `TabView`: past five tabs, iPhone moves the rest
//  into a "More" navigation controller, which put a stray back button (and,
//  behind it, a system list of tabs) on Community and You.
//
//  The shell's state — the tab, what is pushed where, cross-tab hand-offs,
//  the account sheet — is a `TabRouter`, built once, because each page is too
//  (see `TabRouter` for why that matters). Cross-tab jumps go through its
//  `pendingPractice`: Home's ritual card names a Practice section, the router
//  switches tabs, and PracticeRoot consumes the request on appear.
//  `pendingProgram` and `pendingRetreat` work the same way (Home and the You
//  tab open a digital retreat; Home's gatherings shelf opens a retreat).
//
//  Browsing needs no account. The gate lives on the router (one sheet for the
//  whole shell) and is handed to the stack roots, which ask for an account
//  only when a guest opens an actual practice — not when they browse the
//  lists.
//

import SwiftUI

/// The primary tabs. `BottomNav` builds itself from `allCases`, so the order
/// here is the order on the bar. (The old Circle placeholder tab was cut from
/// v1 under Guideline 4.2; Community is its real successor — a live feed, not
/// a promise.)
///
/// `programs` is the Digital Retreats tab. Members only ever see "digital
/// retreat"; the code, the tables and the `-tab programs` launch arg keep the
/// original name.
enum MainTab: String, Hashable, CaseIterable {
    case home, gatherings, programs, practice, community, you

    var label: String {
        switch self {
        case .home:       return "Home"
        case .gatherings: return "Gatherings"
        case .programs:   return "Digital Retreats"
        case .practice:   return "Practice"
        case .community:  return "Community"
        case .you:        return "You"
        }
    }

    var systemImage: String {
        switch self {
        case .home:       return "house"
        case .gatherings: return "mountain.2"
        case .programs:   return "sun.horizon"
        case .practice:   return "figure.mind.and.body"
        case .community:  return "person.2"
        case .you:        return "person.crop.circle"
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var app
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    /// Forwarded into each tab through the router (`TabPage`): written
    /// practices time themselves by it, and a hosting controller of our own
    /// doesn't inherit it from the scene the way a SwiftUI child would.
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = TabRouter(tab: Self.initialTab)

    /// DEBUG launch hook matching the `-preview-*` family in
    /// `SoulfullGatheringsApp`: `-tab practice` opens straight to a tab for a
    /// visual pass without hand-driving the app. Always `.home` in Release.
    private static var initialTab: MainTab {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count,
           let tab = MainTab(rawValue: args[i + 1]) {
            return tab
        }
        if args.contains("-preview-you") { return .you }
        if args.contains("-preview-community") { return .community }
        #endif
        return .home
    }
    /// Bumped when a member signs out or deletes their account, which rebuilds
    /// every tab from scratch. Tabs keep their screens and view models while
    /// another is showing; without this, a guest inherited the last member's
    /// pushed pages (a journal entry left open by a cross-tab jump) and their
    /// half-filled screens. Not bumped on sign-in: the account gate replays
    /// the interrupted tap into the tab it came from, which must still exist.
    @State private var shell = 0
    private let push = PushRegistrar.shared

    /// Whether the account gate lets a tap straight through. `-preview-
    /// instructors` browses its fixture as a member (DEBUG only — the flag is
    /// always false in Release), so a fixture practice page can be opened.
    private static func hasAccount(_ auth: AuthManager) -> Bool {
        auth.hasAccount || InstructorDirectory.isPreviewMember
    }

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            TabPager(selection: router.tab, makePage: page)
                // Edge to edge: each tab's hosting controller takes its safe
                // area (and keyboard avoidance) from the window itself.
                .ignoresSafeArea()
                .id(shell)

            // Docked nav. Static: it hides on detail pushes without moving.
            BottomNav(current: $router.tab)
                .opacity(router.isNavHidden ? 0 : 1)
                .allowsHitTesting(!router.isNavHidden)
                .transaction { $0.animation = nil }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            router.scenePhase = phase
        }
        // Member → guest: sign-out, deletion, or a session lost for good. Keyed
        // on `isAnonymous`, the identity itself: a member whose session is
        // merely being retried is still that member.
        .onChange(of: auth.isAnonymous) { wasGuest, isGuest in
            guard !wasGuest, isGuest else { return }
            router.pushed = []
            shell += 1
        }
        .onChange(of: push.openNotificationsRequested, initial: true) { _, requested in
            guard requested else { return }
            push.openNotificationsRequested = false
            router.openNotifications()
        }
        // A program's morning nudge was tapped: the same hand-off as Home's
        // "Day N is open" card, which lands on the open day.
        .onChange(of: push.openProgramRequested, initial: true) { _, programID in
            guard let programID else { return }
            push.openProgramRequested = nil
            router.openProgram(programID)
        }
        // One sheet for the whole shell, so a gated tap works from any tab and
        // survives the tab switch Home's ritual card performs.
        .sheet(isPresented: $router.showAccount, onDismiss: {
            router.resumeAfterAccountSheet(signedIn: Self.hasAccount(auth))
        }) {
            AccountView(initialName: settings.name)
        }
    }

    /// One tab, ready for its own hosting controller, built once — when the
    /// tab is first selected — and never again (see `TabRouter`). Everything a
    /// SwiftUI child would inherit from above is handed over explicitly — the
    /// app's observable objects, dark mode, the tint and, through the router,
    /// the scene phase — because a `UIHostingController` starts a fresh
    /// environment.
    ///
    /// The offline / failed-session banner is an inset on each tab root and
    /// pushed screen (`connectionBannerInset`), not an overlay here, so it
    /// never covers a Back link.
    private func page(_ item: MainTab) -> AnyView {
        AnyView(
            TabPage(router: router) { content(item) }
                .ignoresSafeArea(.keyboard)
                .environment(app)
                .environment(settings)
                .environment(auth)
                .environment(\.colorScheme, .dark)
                .tint(Theme.ink)
        )
    }

    /// Closures over the router and the app's objects only — references that
    /// outlive this view value — never over this view's own state, which a
    /// page built once would hold a stale copy of.
    @ViewBuilder
    private func content(_ item: MainTab) -> some View {
        @Bindable var router = router
        let auth = auth
        let requireAccount: (@escaping () -> Void) -> Void = { [router] action in
            router.requireAccount(signedIn: Self.hasAccount(auth), action)
        }
        switch item {
        case .home:
            HomeView(onOpenRetreats: { router.tab = .gatherings },
                     onOpenRetreat: { router.openRetreat($0) },
                     onOpenPractice: { router.openPractice($0) },
                     onOpenProgram: { router.openProgram($0) })
            .connectionBannerInset()
        case .gatherings:
            GatheringsRoot(navHidden: router.navHidden(.gatherings), pending: $router.pendingRetreat,
                           onGoHome: { router.tab = .home })
        case .programs:
            ProgramsRoot(navHidden: router.navHidden(.programs), pending: $router.pendingProgram,
                         requireAccount: requireAccount)
        case .practice:
            PracticeRoot(navHidden: router.navHidden(.practice), pending: $router.pendingPractice,
                         requireAccount: requireAccount,
                         onOpenProgram: { router.openProgram($0) })
        case .community:
            CommunityRoot(navHidden: router.navHidden(.community),
                          openNotifications: $router.pendingNotifications,
                          requireAccount: requireAccount,
                          onOpenProfile: { router.tab = .you })
        case .you:
            ProfileView(onOpenProgram: { router.openProgram($0) },
                        onOpenRetreats: { router.tab = .gatherings })
            .connectionBannerInset()
        }
    }
}

/// A tab's page under the scene phase the router carries. The one thing from
/// above a page needs that changes while the app runs; read here, a change
/// re-renders this wrapper and whoever reads the phase, not the whole page.
private struct TabPage<Content: View>: View {
    let router: TabRouter
    @ViewBuilder let content: Content

    var body: some View {
        content.environment(\.scenePhase, router.scenePhase)
    }
}

// MARK: - Gatherings wrapped in its own NavigationStack so retreats push correctly.

/// The Gatherings tab: the retreats stack, and everything a retreat leads to.
/// Home's shelf of upcoming gatherings hands off here rather than pushing on
/// its own stack — the same way its digital retreats shelf hands off to that
/// tab — so there is one place a retreat is opened from.
private struct GatheringsRoot: View {
    enum Route: Hashable {
        case retreatDetail(Retreat)
        // Post-purchase flow (experience hub → trip screens).
        case retreatExperience(Retreat)
        case retreatTodos(Retreat)
        case retreatGuides(Retreat)
        case retreatPacking(Retreat)
    }
    @Binding var navHidden: Bool
    /// A retreat another tab asked to open. The stack consumes it once its
    /// catalog is in, then clears it.
    @Binding var pending: Retreat?
    /// The trip checklist's "Go to my home" — the Home tab, not this root.
    var onGoHome: () -> Void = {}
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            // Replaces the path rather than appending: the root only calls this
            // with nothing pushed, except for a hand-off, which may arrive while
            // the tab is still holding a screen from an earlier visit.
            RetreatsStackView(isTabRoot: true, pending: $pending,
                              onSelect: { r in path = [.retreatDetail(r)] })
                .connectionBannerInset()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .toolbar(.hidden, for: .navigationBar)
                        .connectionBannerInset()
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: path) { navHidden = !path.isEmpty }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .retreatDetail(let r):
            // Detail screen wired to push the post-purchase flow (the hub).
            RetreatDetailView(
                retreat: r,
                onOpenExperience: { path.append(.retreatExperience($0)) }
            )

        case .retreatExperience(let r):
            RetreatExperienceHubView(
                retreat: r,
                onOpenTodos:   { path.append(.retreatTodos(r)) },
                onOpenGuides:  { path.append(.retreatGuides(r)) },
                onOpenPacking: { path.append(.retreatPacking(r)) },
                onOpenDetail:  { path.append(.retreatDetail(r)) }
            )

        case .retreatTodos(let r):
            RetreatTodosView(retreat: r, onGoHome: onGoHome)
        case .retreatGuides(let r):
            RetreatGuidesView(retreat: r)
        case .retreatPacking(let r):
            PackingListView(retreat: r)
        }
    }
}

// MARK: - Programs wrapped in its own NavigationStack.

/// The Programs tab (labelled Digital Retreats). Browsing is open to a guest
/// all the way down to the day list; `requireAccount` wraps **joining** only — the moment a program stops
/// being something you're reading about and starts being yours.
private struct ProgramsRoot: View {
    enum Route: Hashable {
        case detail(Program)
        /// The day by NUMBER rather than by value, and both pages draw the
        /// catalog's current copy of the program (`LiveProgram`): a curriculum
        /// can be re-authored under a live member, and a stale copy sitting in
        /// the navigation path would keep rendering the old one. The `Program`
        /// carried here is only the fallback.
        case day(Program, Int)
        case journalDetail(JournalPrompt)
        case exerciseDetail(Exercise)
        case recipeDetail(Recipe)
        /// A guide's profile, from the "Your guide" card on a digital retreat
        /// or a practice. `from` is the back bar's label — that page's title.
        case instructor(String, from: String)
    }
    @Binding var navHidden: Bool
    /// A program another tab asked to open. Consumed once, then cleared.
    @Binding var pending: String?
    var requireAccount: (@escaping () -> Void) -> Void = { $0() }
    @State private var path: [Route] = []
    @State private var catalog = ProgramsViewModel()

    var body: some View {
        NavigationStack(path: $path) {
            // Replace rather than append, as on the Gatherings tab: a hand-off
            // can arrive while the tab is holding a screen from an earlier visit.
            ProgramsView(
                onOpenProgram: { path = [.detail($0)] },
                onOpenDay: { program, day in path = [.day(program, day.day)] },
                pending: $pending,
                vm: catalog
            )
            .connectionBannerInset()
            .navigationDestination(for: Route.self) { route in
                destination(route)
                    .toolbar(.hidden, for: .navigationBar)
                    .connectionBannerInset()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.openInstructor) { id, from in openInstructor(id, from: from) }
        .onChange(of: path) { navHidden = !path.isEmpty }
    }

    /// Pushes a guide's profile — unless it is already in the stack: on top
    /// (where a session's player was opened from when its guide chip is
    /// tapped) it stays put, and further down it is popped back to, so
    /// profile → recipe → "Your guide" doesn't grow a second copy of the same
    /// profile for Back to walk through.
    private func openInstructor(_ id: String, from: String) {
        if let index = path.lastIndex(where: {
            if case .instructor(let open, _) = $0 { return open == id }
            return false
        }) {
            path.removeLast(path.count - 1 - index)
            return
        }
        path.append(.instructor(id, from: from))
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .detail(let pushed):
            LiveProgram(pushed: pushed, catalog: catalog) { program in
                ProgramDetailView(
                    program: program,
                    onOpenDay: { path.append(.day(program, $0.day)) },
                    requireAccount: requireAccount
                )
            }

        case .day(let pushed, let number):
            LiveProgram(pushed: pushed, catalog: catalog) { program in
                if let day = program.authoredDays.first(where: { $0.day == number }) {
                    ProgramDayView(program: program, day: day, onOpen: open)
                }
            }

        case .journalDetail(let prompt):  JournalDetailView(prompt: prompt)
        case .exerciseDetail(let exercise): ExerciseDetailView(exercise: exercise)
        case .recipeDetail(let recipe):   RecipeDetailView(recipe: recipe)

        case .instructor(let id, let from):
            InstructorProfileView(instructorID: id, backLabel: from,
                                  onOpenProgram: { path.append(.detail($0)) },
                                  onOpenPractice: { content in requireAccount { open(content) } },
                                  requireAccount: requireAccount)
        }
    }

    /// A day's activity opens the *same* screen the Practice tab would open, so
    /// it records to the same ledger and a creator is paid identically either
    /// way. Sessions are a sheet and stay inside `ProgramDayView`.
    private func open(_ content: ProgramActivityContent) {
        switch content {
        case .journal(let prompt):    path.append(.journalDetail(prompt))
        case .exercise(let exercise): path.append(.exerciseDetail(exercise))
        case .recipe(let recipe):     path.append(.recipeDetail(recipe))
        case .session:                break   // handled as a sheet by the day view
        }
    }
}

/// A digital retreat's page, drawn from the catalog's current copy of the
/// program rather than the one it was pushed with.
///
/// The route carries the whole `Program`, curriculum included, and drawing
/// that kept a day or detail page on the curriculum as it was when pushed —
/// and `ProgramStore.syncCompletion` judged the day against it — however it
/// had been re-authored since. Each page re-reads the catalog as it appears
/// (from the five-minute cache), which is how an edit reaches a page someone
/// comes back to.
private struct LiveProgram<Page: View>: View {
    let pushed: Program
    let catalog: ProgramsViewModel
    @ViewBuilder let page: (Program) -> Page

    var body: some View {
        page(catalog.current(pushed))
            .task { await catalog.load() }
    }
}

// MARK: - Community wrapped in its own NavigationStack.

/// The Community tab. The feed is open to a guest; the Friends filter and the
/// Friends screen go through `requireAccount`, the same gate as a practice.
/// The view model is owned here so the feed and the Friends screen share one
/// set of friendships — accepting a request on one is reflected on the other
/// without a round trip.
private struct CommunityRoot: View {
    enum Route: Hashable {
        case friends
        case notifications
    }
    @Binding var navHidden: Bool
    /// A like push was tapped. Consumed once, then cleared.
    @Binding var openNotifications: Bool
    var requireAccount: (@escaping () -> Void) -> Void = { $0() }
    /// Switch to the You tab, where the profile photo is set.
    var onOpenProfile: () -> Void = {}
    @State private var path: [Route] = []
    @State private var vm = CommunityViewModel()

    var body: some View {
        NavigationStack(path: $path) {
            CommunityView(vm: vm,
                          onOpenFriends: { path.append(.friends) },
                          onOpenNotifications: { path.append(.notifications) },
                          onOpenProfile: onOpenProfile,
                          requireAccount: requireAccount)
                .connectionBannerInset()
                .onAppear(perform: consumeOpenNotifications)
                .onChange(of: openNotifications) { consumeOpenNotifications() }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .friends:
                        FriendsView(vm: vm)
                            .toolbar(.hidden, for: .navigationBar)
                            .connectionBannerInset()
                    case .notifications:
                        NotificationsView(vm: vm)
                            .toolbar(.hidden, for: .navigationBar)
                            .connectionBannerInset()
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: path) { navHidden = !path.isEmpty }
    }

    private func consumeOpenNotifications() {
        guard openNotifications else { return }
        openNotifications = false
        path = [.notifications]
        // The like that was just tapped: with Notifications already on top,
        // setting the path recreates nothing, so read the list here — the
        // screen then marks the new row read as it arrives.
        Task { await vm.loadNotifications(force: true) }
    }
}

// MARK: - Practice wrapped in its own NavigationStack so category lists push correctly.

private struct PracticeRoot: View {
    enum Route: Hashable {
        case sessions(PracticeCategory)
        case journalList
        case exerciseList
        case recipeList
        case journalDetail(JournalPrompt)
        case exerciseDetail(Exercise)
        case recipeDetail(Recipe)
        /// A guide's profile, from the "Your guide" card on a practice's page.
        /// `from` is the back bar's label — that page's title.
        case instructor(String, from: String)
    }
    @Binding var navHidden: Bool
    /// A section another tab asked to open. Consumed once, then cleared.
    @Binding var pending: PracticeMenuItem?
    /// Runs the action once an account exists, raising the account sheet first
    /// if the user is still a guest. Wraps only the *doing* — playing a
    /// session, opening a prompt, a movement sequence, a recipe. The landing
    /// and every list stay open, so a guest can always see what's on offer.
    var requireAccount: (@escaping () -> Void) -> Void = { $0() }
    /// A digital retreat in a guide's library. Programs live on their own
    /// tab, so it is handed there rather than pushed here — one place a
    /// digital retreat is opened from, as with Home's shelf.
    var onOpenProgram: (String) -> Void = { _ in }
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            PracticeView(onSelect: open)
                .connectionBannerInset()
                .onAppear(perform: consumePending)
                .onChange(of: pending) { consumePending() }
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .toolbar(.hidden, for: .navigationBar)
                        .connectionBannerInset()
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.openInstructor) { id, from in openInstructor(id, from: from) }
        .onChange(of: path) { navHidden = !path.isEmpty }
    }

    /// Pushes a guide's profile — unless it is already in the stack: on top
    /// (where a session's player was opened from when its guide chip is
    /// tapped) it stays put, and further down it is popped back to, so
    /// profile → recipe → "Your guide" doesn't grow a second copy of the same
    /// profile for Back to walk through.
    private func openInstructor(_ id: String, from: String) {
        if let index = path.lastIndex(where: {
            if case .instructor(let open, _) = $0 { return open == id }
            return false
        }) {
            path.removeLast(path.count - 1 - index)
            return
        }
        path.append(.instructor(id, from: from))
    }

    /// Opens whatever another tab handed us, then clears it so returning to
    /// this tab later doesn't re-push the same screen.
    private func consumePending() {
        guard let item = pending else { return }
        pending = nil
        path = []
        open(item)
    }

    /// Maps a tapped menu card to its list route.
    private func open(_ item: PracticeMenuItem) {
        switch item {
        case .somatic, .breathwork, .meditation:
            if let category = item.mediaCategory { path.append(.sessions(category)) }
        case .journal:  path.append(.journalList)
        case .movement: path.append(.exerciseList)
        case .recipes:  path.append(.recipeList)
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .sessions(let category):
            PracticeListView(category: category, requireAccount: requireAccount)
        case .journalList:
            JournalListView(onOpen: { p in requireAccount { path.append(.journalDetail(p)) } })
        case .exerciseList:
            ExerciseListView(onOpen: { e in requireAccount { path.append(.exerciseDetail(e)) } })
        case .recipeList:
            RecipeListView(onOpen: { r in requireAccount { path.append(.recipeDetail(r)) } })
        case .journalDetail(let prompt):
            JournalDetailView(prompt: prompt)
        case .exerciseDetail(let exercise):
            ExerciseDetailView(exercise: exercise)
        case .recipeDetail(let recipe):
            RecipeDetailView(recipe: recipe)
        case .instructor(let id, let from):
            InstructorProfileView(instructorID: id, backLabel: from,
                                  onOpenProgram: { onOpenProgram($0.id) },
                                  onOpenPractice: { content in
                                      requireAccount {
                                          switch content {
                                          case .journal(let prompt):    path.append(.journalDetail(prompt))
                                          case .exercise(let exercise): path.append(.exerciseDetail(exercise))
                                          case .recipe(let recipe):     path.append(.recipeDetail(recipe))
                                          case .session:                break   // played in the profile's own sheet
                                          }
                                      }
                                  },
                                  requireAccount: requireAccount)
        }
    }
}

// MARK: - Tab pager

/// What `UITabBarController` does for the tabs, minus the bar and minus its
/// five-tab limit: one hosting controller per tab, made the first time the tab
/// is shown and kept from then on, with only the selected one in the window.
/// Keeping it is what keeps the tab's state; taking it out of the window is
/// what pauses it and runs its `.task`s again when it comes back.
private struct TabPager: UIViewControllerRepresentable {
    let selection: MainTab
    /// Builds a tab's page. Called once per tab, when it is first selected.
    let makePage: (MainTab) -> AnyView

    func makeUIViewController(context: Context) -> TabPagerController {
        TabPagerController()
    }

    func updateUIViewController(_ controller: TabPagerController, context: Context) {
        controller.show(selection, makePage: makePage)
    }
}

final class TabPagerController: UIViewController {
    private var hosts: [MainTab: UIHostingController<AnyView>] = [:]
    private var showing: MainTab?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func show(_ selection: MainTab, makePage: (MainTab) -> AnyView) {
        // A tab is made once, when it is first selected, and its page is
        // never handed over again. Every update used to give each made tab a
        // freshly built page, which re-ran every open tab's body for a push
        // on any one of them. What a page shows that can change reaches it
        // through `TabRouter`.
        if hosts[selection] == nil {
            let host = UIHostingController(rootView: makePage(selection))
            host.view.backgroundColor = .clear
            host.overrideUserInterfaceStyle = .dark
            addChild(host)
            host.didMove(toParent: self)
            hosts[selection] = host
        }
        guard showing != selection, let host = hosts[selection] else { return }
        if let showing, let previous = hosts[showing] {
            previous.view.removeFromSuperview()
        }
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        showing = selection
    }
}

#Preview {
    let a = AppState()
    return MainTabView()
        .environment(a)
        .environment(a.settings)
        .environment(a.auth)
}
