//
//  RootView.swift
//  Soulfull Gatherings
//
//  Stage router. Stages hand off through an organic noise dissolve (plain
//  fade under Reduce Motion). Loading is a breathing logo over aurora — the
//  first thing a user sees, so it already speaks the brand.
//

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            switch app.stage {
            case .loading:
                loadingStage
                    .transition(.soulStage(reduceMotion: reduceMotion))
            case .welcome:
                WelcomeView()
                    .transition(.soulStage(reduceMotion: reduceMotion))
            case .onboarding:
                // Native transition: onboarding's TextField is UIKit-backed and
                // cannot sit under the dissolve's layerEffect (yellow placeholder).
                OnboardingView()
                    .transition(reduceMotion ? .opacity : .editorialPageSoft)
            case .main:
                // NavigationStack is UIKit-backed and can't be shader-rasterized
                // (yellow placeholder) — main gets a native blur-scale handoff.
                MainTabView()
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.04).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.9), value: app.stage)
    }

    private var loadingStage: some View {
        ZStack {
            AuroraBackground(speed: 1.2)
                .filmGrain()
                .ignoresSafeArea()

            Image("soulfull-logo-white")
                .resizable().scaledToFit()
                .frame(width: 150, height: 150)
                .breathing(period: 4.5)
                .shadow(color: .white.opacity(0.15), radius: 30)
        }
    }
}

#Preview {
    RootView().environment(AppState())
}
