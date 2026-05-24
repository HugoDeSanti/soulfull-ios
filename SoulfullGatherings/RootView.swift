//
//  RootView.swift
//  Soulfull Gatherings
//
//  Stage router. Switches between Welcome / Onboarding / Main with a
//  soft cross-fade. Each stage is a self-contained screen.
//

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            switch app.stage {
            case .welcome:
                WelcomeView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .main:
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: app.stage)
    }
}

#Preview {
    RootView().environment(AppState())
}
