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

    init() {
        #if DEBUG
        // UI-test hooks: deterministic state for the automated tour.
        if CommandLine.arguments.contains("-uitest-reset") {
            appState.settings.reset()
        }
        if CommandLine.arguments.contains("-uitest-onboarded") {
            appState.settings.userName = "Mara"
            appState.settings.hasOnboarded = true
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .environment(appState)
                .environment(appState.settings)
                .environment(appState.auth)
                .preferredColorScheme(.dark)
                .tint(Theme.ink)
                .task { await appState.initializeAuth() }
                .onOpenURL { url in
                    // Email-confirmation / magic-link callback (soulfull://auth-callback).
                    Task { await appState.auth.handleDeepLink(url) }
                }
        }
    }

    /// The app root, or a DEBUG screen override for visual passes without
    /// driving the full app to it (`-preview-checkout` / `-preview-experience`
    /// launch args). Release builds always show `RootView`.
    @ViewBuilder private var rootContent: some View {
        #if DEBUG
        if CommandLine.arguments.contains("-preview-retreat") {
            NavigationStack {
                RetreatDetailView(retreat: .mock[0]).toolbar(.hidden, for: .navigationBar)
            }
        } else if CommandLine.arguments.contains("-preview-checkout") {
            NavigationStack {
                RetreatCheckoutView(retreat: .mock[0]).toolbar(.hidden, for: .navigationBar)
            }
        } else if CommandLine.arguments.contains("-preview-experience") {
            NavigationStack {
                RetreatExperienceHubView(retreat: .mock[0]).toolbar(.hidden, for: .navigationBar)
            }
        } else if CommandLine.arguments.contains("-preview-todos") {
            NavigationStack {
                RetreatTodosView(retreat: .mock[0]).toolbar(.hidden, for: .navigationBar)
            }
        } else if CommandLine.arguments.contains("-preview-packing") {
            NavigationStack {
                PackingListView(retreat: .mock[0]).toolbar(.hidden, for: .navigationBar)
            }
        } else if CommandLine.arguments.contains("-preview-guides") {
            NavigationStack {
                RetreatGuidesView(retreat: .mock[0]).toolbar(.hidden, for: .navigationBar)
            }
        } else if CommandLine.arguments.contains("-preview-confirm-email") {
            AccountView(previewConfirmationFor: "hugo@soulfullgatherings.com")
        } else if CommandLine.arguments.contains("-preview-chat") {
            NavigationStack {
                RetreatAssistantView(retreat: .mock[0]).toolbar(.hidden, for: .navigationBar)
            }
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
