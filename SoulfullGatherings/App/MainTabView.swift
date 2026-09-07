//
//  MainTabView.swift
//  Soulfull Gatherings
//
//  Hosts the primary tabs (Home, Practice, You — Circle is cut from v1, see
//  AppFeatures.circleTabEnabled) with a custom floating glass tab bar instead
//  of the system one. Home pushes into Retreats / Retreat Detail through its
//  own NavigationStack so native swipe-back works.
//
//  Cross-tab jumps go through `pendingPractice`: Home's ritual card names a
//  Practice section, MainTabView switches tabs, and PracticeRoot consumes the
//  request on appear.
//
//  Browsing needs no account. `AccountGate` lives here (one sheet for the whole
//  shell) and is handed to PracticeRoot, which asks for an account only when a
//  guest opens an actual practice — not when they browse the lists.
//

import SwiftUI

/// The primary tabs. `BottomNav` builds itself from `allCases`, so adding the
/// Circle case back is all that's needed to restore the tab — see
/// `AppFeatures.circleTabEnabled` for why it's out of v1.
enum MainTab: String, Hashable, CaseIterable {
    case home, practice, you

    var label: String {
        switch self {
        case .home:     return "Home"
        case .practice: return "Practice"
        case .you:      return "You"
        }
    }

    var systemImage: String {
        switch self {
        case .home:     return "house"
        case .practice: return "sparkles"
        case .you:      return "person.crop.circle"
        }
    }

    /// Filled variant shown while the tab is selected.
    var activeSystemImage: String {
        switch self {
        case .home:     return "house.fill"
        case .practice: return "sparkles"
        case .you:      return "person.crop.circle.fill"
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

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch tab {
                case .home:
                    HomeRoot(navHidden: $navHidden) { item in
                        pendingPractice = item
                        tab = .practice
                    }
                case .practice:
                    PracticeRoot(navHidden: $navHidden, pending: $pendingPractice,
                                 requireAccount: { action in
                                     if gate.require(signedIn: auth.hasAccount, action) {
                                         showAccount = true
                                     }
                                 })
                case .you:      ProfilePlaceholder()
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

            // Floating glass nav
            BottomNav(current: $tab)
                .padding(.bottom, 8)
                .offset(y: navHidden ? 140 : 0)
                .opacity(navHidden ? 0 : 1)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: navHidden)
        }
        .onChange(of: tab) { navHidden = false }
        // One sheet for the whole shell, so a gated tap works from any tab and
        // survives the tab switch Home's ritual card performs.
        .sheet(isPresented: $showAccount, onDismiss: {
            gate.resume(signedIn: auth.hasAccount)
        }) {
            AccountView(initialName: settings.userName)
        }
    }
}

// MARK: - Home wrapped in its own NavigationStack so retreats push correctly.

private struct HomeRoot: View {
    enum Route: Hashable {
        case retreatsStack
        /// `zoom` is true when pushed from a Home card that registered a
        /// matched zoom-hero source; pushes from the retreats stack use the
        /// default slide (the full-bleed photo already carries continuity).
        case retreatDetail(Retreat, zoom: Bool)
        // Post-purchase flow (reserve → experience hub → trip screens).
        case retreatCheckout(Retreat)
        case retreatExperience(Retreat)
        case retreatTodos(Retreat)
        case retreatGuides(Retreat)
        case retreatPacking(Retreat)
        case retreatChat(Retreat)
    }
    @Binding var navHidden: Bool
    /// Switch to the Practice tab and open a section there.
    var onOpenPractice: (PracticeMenuItem) -> Void = { _ in }
    @State private var path: [Route] = []
    @Namespace private var zoomNS

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onOpenRetreats: { path.append(.retreatsStack) },
                onOpenRetreat: { r in path.append(.retreatDetail(r, zoom: true)) },
                onOpenPractice: onOpenPractice,
                zoomNamespace: zoomNS
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .retreatsStack:
                    RetreatsStackView(
                        onSelect: { r in path.append(.retreatDetail(r, zoom: false)) }
                    )
                    .toolbar(.hidden, for: .navigationBar)

                case .retreatDetail(let r, let zoom):
                    Group {
                        if zoom {
                            retreatDetail(r)
                                .navigationTransition(.zoom(sourceID: "home-retreat-\(r.id)", in: zoomNS))
                        } else {
                            retreatDetail(r)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)

                case .retreatCheckout(let r):
                    RetreatCheckoutView(retreat: r, onReserved: { path = [.retreatExperience(r)] })
                        .toolbar(.hidden, for: .navigationBar)

                case .retreatExperience(let r):
                    RetreatExperienceHubView(
                        retreat: r,
                        onOpenTodos:   { path.append(.retreatTodos(r)) },
                        onOpenGuides:  { path.append(.retreatGuides(r)) },
                        onOpenPacking: { path.append(.retreatPacking(r)) },
                        onOpenChat:    { path.append(.retreatChat(r)) },
                        onOpenDetail:  { path.append(.retreatDetail(r, zoom: false)) }
                    )
                    .toolbar(.hidden, for: .navigationBar)

                case .retreatTodos(let r):
                    RetreatTodosView(retreat: r, onGoHome: { path = [] })
                        .toolbar(.hidden, for: .navigationBar)
                case .retreatGuides(let r):
                    RetreatGuidesView(retreat: r)
                        .toolbar(.hidden, for: .navigationBar)
                case .retreatPacking(let r):
                    PackingListView(retreat: r)
                        .toolbar(.hidden, for: .navigationBar)
                case .retreatChat(let r):
                    RetreatAssistantView(retreat: r)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: path) { navHidden = !path.isEmpty }
    }

    /// Detail screen wired to push the post-purchase flow (checkout / hub).
    private func retreatDetail(_ r: Retreat) -> some View {
        RetreatDetailView(
            retreat: r,
            onCheckout: { path.append(.retreatCheckout($0)) },
            onOpenExperience: { path.append(.retreatExperience($0)) }
        )
    }
}

// MARK: - Practice wrapped in its own NavigationStack so category lists push correctly.

private struct PracticeRoot: View {
    enum Route: Hashable {
        case sessions(PracticeCategory)
        case journalList
        case exerciseList
        case recipeList
        case massageList
        case journalDetail(JournalPrompt)
        case exerciseDetail(Exercise)
        case recipeDetail(Recipe)
        case massageDetail(Massage)
    }
    @Binding var navHidden: Bool
    /// A section another tab asked to open. Consumed once, then cleared.
    @Binding var pending: PracticeMenuItem?
    /// Runs the action once an account exists, raising the account sheet first
    /// if the user is still a guest. Wraps only the *doing* — playing a
    /// session, opening a prompt, an exercise, a recipe, a massage. The landing
    /// and every list stay open, so a guest can always see what's on offer.
    var requireAccount: (@escaping () -> Void) -> Void = { $0() }
    @State private var path: [Route] = []
    @Namespace private var zoomNS

    var body: some View {
        NavigationStack(path: $path) {
            PracticeView(onSelect: open, zoomNamespace: zoomNS)
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
        case .journal:   path.append(.journalList)
        case .exercises: path.append(.exerciseList)
        case .recipes:   path.append(.recipeList)
        case .massages:  path.append(.massageList)
        }
    }

    /// Zoom-hero source registered by the landing card for each list route;
    /// detail routes push normally from within their list.
    private func zoomSourceID(_ route: Route) -> String? {
        switch route {
        case .sessions(let category): return category.rawValue
        case .journalList:            return PracticeMenuItem.journal.rawValue
        case .exerciseList:           return PracticeMenuItem.exercises.rawValue
        case .recipeList:             return PracticeMenuItem.recipes.rawValue
        case .massageList:            return PracticeMenuItem.massages.rawValue
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
        case .massageList:
            MassageListView(onOpen: { m in requireAccount { path.append(.massageDetail(m)) } })
        case .journalDetail(let prompt):
            JournalDetailView(prompt: prompt)
        case .exerciseDetail(let exercise):
            ExerciseDetailView(exercise: exercise)
        case .recipeDetail(let recipe):
            RecipeDetailView(recipe: recipe)
        case .massageDetail(let massage):
            MassageDetailView(massage: massage)
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
