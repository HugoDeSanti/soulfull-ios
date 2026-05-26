//
//  SoulfullGatheringsApp.swift
//  Soulfull Gatherings
//
//  App entry. Owns the single AppState that drives stage routing
//  (loading → welcome → onboarding → main) and anonymous auth via
//  AuthManager. The `.task` initiates auth and transitions out of
//  the loading stage as quickly as the network allows.
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
                .environment(appState.auth)
                .preferredColorScheme(.dark)
                .tint(Theme.ink)
                .task { await appState.initializeAuth() }
        }
    }
}
