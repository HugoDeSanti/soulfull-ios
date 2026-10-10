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
//  Cross-tab jumps go through `pendingPractice`: Home's ritual card names a
//  Practice section, MainTabView switches tabs, and PracticeRoot consumes the
//  request on appear. `pendingProgram` and `pendingRetreat` work the same way
//  (Home and the You tab open a digital retreat; Home's gatherings shelf opens
//  a retreat).
//
//  Browsing needs no account. `AccountGate` lives here (one sheet for the whole
//  shell) and is handed to PracticeRoot, which asks for an account only when a
//  guest opens an actual practice — not when they browse the lists.
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
        case .gatherings: return "map"
        case .programs:   return "mountain.2"
        case .practice:   return "sparkles"
        case .community:  return "person.2"
        case .you:        return "person.crop.circle"
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var app
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    /// Forwarded into each tab (see `page(_:)`): written practices time
    /// themselves by it, and a hosting controller of our own doesn't inherit
    /// it from the scene the way a SwiftUI child would.
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: MainTab = Self.initialTab
    /// Holds an interrupted action while the account sheet is up, then replays
    /// it. Scoped to the tab shell because that's the only place that gates.
    @State private var gate = AccountGate()
    /// Presentation is a plain Bool, not a property of `gate` — see the note in
    /// `AccountGate.swift` for why binding a sheet to an @Observable class's
    /// property left it undismissable.
    @State private var showAccount = false

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
    /// The tabs whose stack has something pushed — on the showing one, the
    /// nav bows out so detail screens own the full canvas. Per tab because
    /// every tab keeps its stack: a hand-off can leave one tab with a screen
    /// pushed and push onto another in the same update, and a single shared
    /// flag ended up with whichever wrote last.
    @State private var pushed: Set<MainTab> = []
    /// Bumped when a member signs out or deletes their account, which rebuilds
    /// every tab from scratch. Tabs keep their screens and view models while
    /// another is showing; without this, a guest inherited the last member's
    /// pushed pages (a journal entry left open by a cross-tab jump) and their
    /// half-filled screens. Not bumped on sign-in: the account gate replays
    /// the interrupted tap into the tab it came from, which must still exist.
    @State private var shell = 0
    /// Set when another tab asks to open a Practice section (Home's ritual
    /// card). `PracticeRoot` consumes and clears it, which is what makes the
    /// jump land on the right screen rather than just the Practice landing.
    @State private var pendingPractice: PracticeMenuItem?
    /// Set when Home's "Day N is open" card asks to open a program. Consumed by
    /// `ProgramsRoot` on appear, the same handshake `pendingPractice` uses.
    @State private var pendingProgram: String?
    /// Set when a card on Home's gatherings shelf asks to open a retreat.
    /// Consumed by `GatheringsRoot` on appear — the same handshake again.
    @State private var pendingRetreat: Retreat?
    /// A like push was tapped. Consumed by `CommunityRoot`, which pushes the
    /// Notifications screen — the same handshake as the others.
    @State private var pendingNotifications = false
    private let push = PushRegistrar.shared

    /// Whether the account gate lets a tap straight through. `-preview-
    /// instructors` browses its fixture as a member (DEBUG only — the flag is
    /// always false in Release), so a fixture practice page can be opened.
    private var hasAccount: Bool { auth.hasAccount || InstructorDirectory.isPreviewMember }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabPager(selection: tab, pages: Dictionary(uniqueKeysWithValues:
                MainTab.allCases.map { ($0, page($0)) }))
                // Edge to edge: each tab's hosting controller takes its safe
                // area (and keyboard avoidance) from the window itself.
                .ignoresSafeArea()
                .id(shell)

            // Docked nav. Static: it hides on detail pushes without moving.
            BottomNav(current: $tab)
                .opacity(navHidden ? 0 : 1)
                .allowsHitTesting(!navHidden)
                .transaction { $0.animation = nil }
        }
        // Member → guest: sign-out, deletion, or a session lost for good. Keyed
        // on `isAnonymous` rather than `hasAccount`, which also dips while a
        // member's session is merely being retried.
        .onChange(of: auth.isAnonymous) { wasGuest, isGuest in
            guard !wasGuest, isGuest else { return }
            pushed = []
            shell += 1
        }
        .onChange(of: push.openNotificationsRequested, initial: true) { _, requested in
            guard requested else { return }
            push.openNotificationsRequested = false
            pendingNotifications = true
            tab = .community
        }
        // A program's morning nudge was tapped: the same hand-off as Home's
        // "Day N is open" card, which lands on the open day.
        .onChange(of: push.openProgramRequested, initial: true) { _, programID in
            guard let programID else { return }
            push.openProgramRequested = nil
            pendingProgram = programID
            tab = .programs
        }
        // One sheet for the whole shell, so a gated tap works from any tab and
        // survives the tab switch Home's ritual card performs.
        .sheet(isPresented: $showAccount, onDismiss: {
            gate.resume(signedIn: hasAccount)
        }) {
            AccountView(initialName: settings.userName)
        }
    }

    /// The showing tab has a screen pushed.
    private var navHidden: Bool { pushed.contains(tab) }

    /// One tab's entry in `pushed`, for its stack root to report through.
    private func navHidden(_ item: MainTab) -> Binding<Bool> {
        Binding(get: { pushed.contains(item) },
                set: { if $0 { pushed.insert(item) } else { pushed.remove(item) } })
    }

    /// One tab, ready for its own hosting controller. Everything a SwiftUI
    /// child would inherit from above is handed over explicitly — the app's
    /// observable objects, dark mode, the tint and the scene phase — because a
    /// `UIHostingController` starts a fresh environment.
    ///
    /// The offline / failed-session banner is an inset on each tab root and
    /// pushed screen (`connectionBannerInset`), not an overlay here, so it
    /// never covers a Back link.
    private func page(_ item: MainTab) -> AnyView {
        AnyView(
            content(item)
                .ignoresSafeArea(.keyboard)
                .environment(app)
                .environment(settings)
                .environment(auth)
                .environment(\.scenePhase, scenePhase)
                .environment(\.colorScheme, .dark)
                .tint(Theme.ink)
        )
    }

    @ViewBuilder
    private func content(_ item: MainTab) -> some View {
        switch item {
        case .home:
            HomeView(onOpenRetreats: { tab = .gatherings },
                     onOpenRetreat: { retreat in
                pendingRetreat = retreat
                tab = .gatherings
            }, onOpenPractice: { item in
                pendingPractice = item
                tab = .practice
            }, onOpenProgram: { programID in
                pendingProgram = programID
                tab = .programs
            })
            .connectionBannerInset()
        case .gatherings:
            GatheringsRoot(navHidden: navHidden(.gatherings), pending: $pendingRetreat,
                           onGoHome: { tab = .home })
        case .programs:
            ProgramsRoot(navHidden: navHidden(.programs), pending: $pendingProgram,
                         requireAccount: { action in
                             if gate.require(signedIn: hasAccount, action) {
                                 showAccount = true
                             }
                         })
        case .practice:
            PracticeRoot(navHidden: navHidden(.practice), pending: $pendingPractice,
                         requireAccount: { action in
                             if gate.require(signedIn: hasAccount, action) {
                                 showAccount = true
                             }
                         },
                         onOpenProgram: { programID in
                             pendingProgram = programID
                             tab = .programs
                         })
        case .community:
            CommunityRoot(navHidden: navHidden(.community), openNotifications: $pendingNotifications,
                          requireAccount: { action in
                              if gate.require(signedIn: hasAccount, action) {
                                  showAccount = true
                              }
                          },
                          onOpenProfile: { tab = .you })
        case .you:
            ProfileView(onOpenProgram: { programID in
                pendingProgram = programID
                tab = .programs
            }, onOpenRetreats: { tab = .gatherings })
            .connectionBannerInset()
        }
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
        /// `zoom` is true only when pushed from a catalog card that registered
        /// a matched source. The continue card and the cross-tab hand-off
        /// register none, and a zoom transition with no source to grow from is
        /// a worse push than a plain one.
        case detail(Program, zoom: Bool)
        /// The day by NUMBER rather than by value: `ProgramDay` is content that
        /// can be re-authored under a live member, and a stale copy sitting in
        /// the navigation path would keep rendering the old one.
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
    @Namespace private var zoomNS

    var body: some View {
        NavigationStack(path: $path) {
            // Replace rather than append, as on the Gatherings tab: a hand-off
            // can arrive while the tab is holding a screen from an earlier visit.
            ProgramsView(
                onOpenProgram: { path = [.detail($0, zoom: $1)] },
                onOpenDay: { program, day in path = [.day(program, day.day)] },
                pending: $pending,
                zoomNamespace: zoomNS
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
        case .detail(let program, let zoom):
            let detail = ProgramDetailView(
                program: program,
                onOpenDay: { path.append(.day(program, $0.day)) },
                requireAccount: requireAccount
            )
            if zoom {
                detail.navigationTransition(.zoom(sourceID: "program-\(program.id)", in: zoomNS))
            } else {
                detail
            }

        case .day(let program, let number):
            if let day = program.authoredDays.first(where: { $0.day == number }) {
                ProgramDayView(program: program, day: day, onOpen: open)
            }

        case .journalDetail(let prompt):  JournalDetailView(prompt: prompt)
        case .exerciseDetail(let exercise): ExerciseDetailView(exercise: exercise)
        case .recipeDetail(let recipe):   RecipeDetailView(recipe: recipe)

        case .instructor(let id, let from):
            InstructorProfileView(instructorID: id, backLabel: from,
                                  onOpenProgram: { path.append(.detail($0, zoom: false)) },
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
    @Namespace private var zoomNS

    var body: some View {
        NavigationStack(path: $path) {
            PracticeView(onSelect: open, zoomNamespace: zoomNS)
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

    /// Zoom-hero source registered by the landing card for each list route;
    /// detail routes push normally from within their list.
    private func zoomSourceID(_ route: Route) -> String? {
        switch route {
        case .sessions(let category): return category.rawValue
        case .journalList:            return PracticeMenuItem.journal.rawValue
        case .exerciseList:           return PracticeMenuItem.movement.rawValue
        case .recipeList:             return PracticeMenuItem.recipes.rawValue
        default:                      return nil
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        if let sourceID = zoomSourceID(route) {
            destinationContent(route)
                .navigationTransition(.zoom(sourceID: sourceID, in: zoomNS))
        } else {
            destinationContent(route)
        }
    }

    @ViewBuilder
    private func destinationContent(_ route: Route) -> some View {
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
    let pages: [MainTab: AnyView]

    func makeUIViewController(context: Context) -> TabPagerController {
        TabPagerController()
    }

    func updateUIViewController(_ controller: TabPagerController, context: Context) {
        controller.show(selection, pages: pages)
    }
}

final class TabPagerController: UIViewController {
    private var hosts: [MainTab: UIHostingController<AnyView>] = [:]
    private var showing: MainTab?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func show(_ selection: MainTab, pages: [MainTab: AnyView]) {
        // Tabs already made get this update's view (fresh closures and
        // environment); a tab is only made once it is first selected.
        for (tab, host) in hosts {
            if let page = pages[tab] { host.rootView = page }
        }
        if hosts[selection] == nil, let page = pages[selection] {
            let host = UIHostingController(rootView: page)
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
