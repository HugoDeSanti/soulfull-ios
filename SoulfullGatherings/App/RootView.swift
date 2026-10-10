//
//  RootView.swift
//  Soulfull Gatherings
//
//  Stage router. Stages hand off through a slow crossfade. Loading is the
//  logo breathing in light on black — the first thing a user sees, so it
//  already speaks the brand: stillness, and space around one thing.
//

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            switch app.stage {
            // Plain opacity for every stage: onboarding's TextField and
            // main's NavigationStacks are UIKit-backed and can't sit under a
            // shader or a blur (rendering gotcha 1), and nothing else should
            // move either.
            case .loading:
                loadingStage
                    .transition(.soulStage)
            case .welcome:
                WelcomeView()
                    .transition(.soulStage)
            case .onboarding:
                OnboardingView(asksName: !app.auth.hasAccount)
                    .transition(.soulStage)
            case .main:
                MainTabView()
                    .transition(.soulStage)
            }
        }
        .animation(Theme.Motion.stage, value: app.stage)
    }

    private var loadingStage: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            Image("soulfull-logo-white")
                .resizable().scaledToFit()
                .frame(width: 96, height: 96)
                .breathing(scale: 1...1, opacity: 0.55...1)
        }
    }
}

#Preview {
    RootView().environment(AppState())
}
