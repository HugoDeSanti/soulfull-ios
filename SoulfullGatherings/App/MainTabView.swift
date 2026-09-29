//
//  MainTabView.swift
//  Soulfull Gatherings
//
//  Hosts the primary tabs (Home, Gatherings, Digital Retreats, Practice,
//  Community, You) with a custom docked tab bar instead of the system one.
//  Gatherings is the retreats stack, pushing into Retreat Detail through its
//  own NavigationStack so native swipe-back works.
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
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
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
    /// True while a tab root has something pushed — the nav bows out so
    /// detail screens own the full canvas.
    @State private var navHidden = false
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

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch tab {
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
                case .gatherings:
                    GatheringsRoot(navHidden: $navHidden, pending: $pendingRetreat,
                                   onGoHome: { tab = .home })
                case .programs:
                    ProgramsRoot(navHidden: $navHidden, pending: $pendingProgram,
                                 requireAccount: { action in
                                     if gate.require(signedIn: auth.hasAccount, action) {
                                         showAccount = true
                                     }
                                 })
                case .practice:
                    PracticeRoot(navHidden: $navHidden, pending: $pendingPractice,
                                 requireAccount: { action in
                                     if gate.require(signedIn: auth.hasAccount, action) {
                                         showAccount = true
                                     }
                                 },
                                 onOpenProgram: { programID in
                                     pendingProgram = programID
                                     tab = .programs
                                 })
                case .community:
                    CommunityRoot(navHidden: $navHidden, openNotifications: $pendingNotifications,
                                  requireAccount: { action in
                                      if gate.require(signedIn: auth.hasAccount, action) {
                                          showAccount = true
                                      }
                                  },
                                  onOpenProfile: { tab = .you })
                case .you:
                    ProfileView(onOpenProgram: { programID in
                        pendingProgram = programID
                        tab = .programs
                    }, onOpenRetreats: { tab = .gatherings })
                }
            }
            .ignoresSafeArea(.keyboard)

            // Offline / failed-session notice, above the content but below the
            // nav. Renders nothing when the session is healthy.
            VStack {
                ConnectionBanner()
                    .padding(.top, 8)
                Spacer()
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: auth.needsRetry)

            // Docked nav. Static: it hides on detail pushes without moving.
            BottomNav(current: $tab)
                .opacity(navHidden ? 0 : 1)
                .allowsHitTesting(!navHidden)
                .transaction { $0.animation = nil }
        }
        .onChange(of: tab) { navHidden = false }
        .onChange(of: push.openNotificationsRequested, initial: true) { _, requested in
            guard requested else { return }
            push.openNotificationsRequested = false
            pendingNotifications = true
            tab = .community
        }
        // One sheet for the whole shell, so a gated tap works from any tab and
        // survives the tab switch Home's ritual card performs.
        .sheet(isPresented: $showAccount, onDismiss: {
            gate.resume(signedIn: auth.hasAccount)
        }) {
            AccountView(initialName: settings.userName)
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
            RetreatsStackView(isTabRoot: true, pending: $pending,
                              onSelect: { r in path.append(.retreatDetail(r)) })
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .toolbar(.hidden, for: .navigationBar)
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
        /// A guide's profile, from a digital retreat's credit. `from` is the
        /// back bar's label — the retreat it was opened from.
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
            ProgramsView(
                onOpenProgram: { path.append(.detail($0, zoom: $1)) },
                onOpenDay: { program, day in path.append(.day(program, day.day)) },
                pending: $pending,
                zoomNamespace: zoomNS
            )
            .navigationDestination(for: Route.self) { route in
                destination(route)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: path) { navHidden = !path.isEmpty }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .detail(let program, let zoom):
            let detail = ProgramDetailView(
                program: program,
                onOpenDay: { path.append(.day(program, $0.day)) },
                requireAccount: requireAccount,
                onOpenInstructor: { path.append(.instructor($0, from: program.title)) }
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
                .onAppear(perform: consumeOpenNotifications)
                .onChange(of: openNotifications) { consumeOpenNotifications() }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .friends:
                        FriendsView(vm: vm)
                            .toolbar(.hidden, for: .navigationBar)
                    case .notifications:
                        NotificationsView(vm: vm)
                            .toolbar(.hidden, for: .navigationBar)
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
        /// A guide's profile, from the Guides shelf.
        case instructor(String)
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
            PracticeView(onSelect: open, zoomNamespace: zoomNS,
                         onOpenInstructor: { path.append(.instructor($0)) })
                .onAppear(perform: consumePending)
                .onChange(of: pending) { consumePending() }
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .toolbar(.hidden, for: .navigationBar)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: path) { navHidden = !path.isEmpty }
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
        case .instructor(let id):
            InstructorProfileView(instructorID: id, backLabel: "Practices",
                                  onOpenProgram: { onOpenProgram($0.id) },
                                  requireAccount: requireAccount)
        }
    }
}

#Preview {
    let a = AppState()
    return MainTabView()
        .environment(a)
        .environment(a.settings)
        .environment(a.auth)
}
