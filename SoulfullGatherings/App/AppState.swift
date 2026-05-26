//
//  AppState.swift
//  Soulfull Gatherings
//
//  Top-level stage routing. Persisted user data lives in `settings`
//  (AppSettings). Auth lives in `auth` (AuthManager).
//

import SwiftUI

@Observable @MainActor
final class AppState {

    enum Stage: Equatable {
        case loading    // while auth initializes
        case welcome
        case onboarding
        case main
    }

    var stage: Stage = .loading

    let settings: AppSettings
    let auth: AuthManager

    init() {
        settings = AppSettings()
        auth = AuthManager()
    }

    /// Called once at launch from `SoulfullGatheringsApp.body` via `.task`.
    /// Establishes auth then routes to the correct stage.
    func initializeAuth() async {
        await auth.initialize()
        let next: Stage = settings.hasOnboarded ? .main : .welcome
        withAnimation(.easeInOut(duration: 0.45)) { stage = next }
    }

    func beginOnboarding() {
        withAnimation(.easeInOut(duration: 0.35)) { stage = .onboarding }
    }

    func finishOnboarding() {
        settings.hasOnboarded = true
        Haptics.success()
        withAnimation(.easeInOut(duration: 0.45)) { stage = .main }
    }

    func finishOnboardingSkipping(name: String) {
        settings.userName = name.trimmingCharacters(in: .whitespaces)
        finishOnboarding()
    }

    /// Used by the in-app "reset onboarding" Profile action (handy during dev).
    func resetAll() {
        settings.reset()
        withAnimation(.easeInOut(duration: 0.35)) { stage = .welcome }
    }
}
