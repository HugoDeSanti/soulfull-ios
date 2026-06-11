//
//  MainTabView.swift
//  Soulfull Gatherings
//
//  Hosts the four primary tabs (Home, Practice, Circle, You) with a custom
//  floating glass tab bar instead of the system one. Home pushes into
//  Retreats / Retreat Detail through its own NavigationStack so native
//  swipe-back works.
//

import SwiftUI

enum MainTab: String, Hashable, CaseIterable {
    case home, practice, circle, you

    var label: String {
        switch self {
        case .home:     return "Home"
        case .practice: return "Practice"
        case .circle:   return "Circle"
        case .you:      return "You"
        }
    }

    var systemImage: String {
        switch self {
        case .home:     return "house"
        case .practice: return "sparkles"
        case .circle:   return "person.2"
        case .you:      return "person.crop.circle"
        }
    }

    /// Filled variant shown while the tab is selected.
    var activeSystemImage: String {
        switch self {
        case .home:     return "house.fill"
        case .practice: return "sparkles"
        case .circle:   return "person.2.fill"
        case .you:      return "person.crop.circle.fill"
        }
    }
}

struct MainTabView: View {
    @State private var tab: MainTab = .home
    /// True while a tab root has something pushed — the nav bows out so
    /// detail screens own the full canvas.
    @State private var navHidden = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch tab {
                case .home:     HomeRoot(navHidden: $navHidden)
                case .practice: PracticeRoot(navHidden: $navHidden)
                case .circle:   CommunityPlaceholder()
                case .you:      ProfilePlaceholder()
                }
            }
            .ignoresSafeArea(.keyboard)

            // Floating glass nav
            BottomNav(current: $tab)
                .padding(.bottom, 8)
                .offset(y: navHidden ? 140 : 0)
                .opacity(navHidden ? 0 : 1)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: navHidden)
        }
        .onChange(of: tab) { navHidden = false }
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
    }
    @Binding var navHidden: Bool
    @State private var path: [Route] = []
    @Namespace private var zoomNS

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onOpenRetreats: { path.append(.retreatsStack) },
                onOpenRetreat: { r in path.append(.retreatDetail(r, zoom: true)) },
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
                    if zoom {
                        RetreatDetailView(retreat: r)
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationTransition(.zoom(sourceID: "home-retreat-\(r.id)", in: zoomNS))
                    } else {
                        RetreatDetailView(retreat: r)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: path) { navHidden = !path.isEmpty }
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
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            PracticeView(onSelect: open)
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .toolbar(.hidden, for: .navigationBar)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: path) { navHidden = !path.isEmpty }
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

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .sessions(let category):
            PracticeListView(category: category)
        case .journalList:
            JournalListView(onOpen: { path.append(.journalDetail($0)) })
        case .exerciseList:
            ExerciseListView(onOpen: { path.append(.exerciseDetail($0)) })
        case .recipeList:
            RecipeListView(onOpen: { path.append(.recipeDetail($0)) })
        case .massageList:
            MassageListView(onOpen: { path.append(.massageDetail($0)) })
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
