//
//  SoulfullGatheringsApp.swift
//  Soulfull Gatherings
//
//  App entry. Owns the single AppState that drives stage routing
//  (welcome → onboarding → main) and persisted user data.
//

import SwiftUI

@main
struct SoulfullGatheringsApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(appState.settings)
                .preferredColorScheme(.dark)
                .tint(Theme.ink)
        }
    }
}
