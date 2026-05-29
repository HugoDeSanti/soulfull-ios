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
}

struct MainTabView: View {
    @State private var tab: MainTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch tab {
                case .home:     HomeRoot()
                case .practice: PracticeRoot()
                case .circle:   CommunityPlaceholder()
                case .you:      ProfilePlaceholder()
                }
            }
            .ignoresSafeArea(.keyboard)

            // Floating glass nav
            BottomNav(current: $tab)
                .padding(.bottom, 8)
        }
    }
}

// MARK: - Home wrapped in its own NavigationStack so retreats push correctly.

private struct HomeRoot: View {
    enum Route: Hashable {
        case retreatsStack
        case retreatDetail(Retreat)
    }
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onOpenRetreats: { path.append(.retreatsStack) },
                onOpenRetreat: { r in path.append(.retreatDetail(r)) }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .retreatsStack:
                    RetreatsStackView(
                        onSelect: { r in path.append(.retreatDetail(r)) }
                    )
                    .toolbar(.hidden, for: .navigationBar)
                case .retreatDetail(let r):
                    RetreatDetailView(retreat: r)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
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
    return MainTabView().environment(a).environment(a.settings)
}
