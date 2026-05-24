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
                case .practice: LibraryPlaceholder()
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

#Preview {
    let a = AppState()
    return MainTabView().environment(a).environment(a.settings)
}
