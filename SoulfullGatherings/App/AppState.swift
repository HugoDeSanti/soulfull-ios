//
//  AppState.swift
//  Soulfull Gatherings
//
//  Top-level stage routing. Persisted user data lives in `settings`
//  (AppSettings), injected into the environment alongside this object.
//

import SwiftUI

@Observable @MainActor
final class AppState {

    enum Stage: Equatable {
        case welcome
        case onboarding
        case main
    }

    var stage: Stage

    let settings: AppSettings

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.stage = settings.hasOnboarded ? .main : .welcome
    }

    func beginOnboarding() {
        withAnimation(.easeInOut(duration: 0.35)) { stage = .onboarding }
    }

    func finishOnboarding() {
        settings.hasOnboarded = true
        Haptics.success()
        withAnimation(.easeInOut(duration: 0.45)) { stage = .main }
    }

    /// Used by the in-app "reset onboarding" Profile action (handy during dev).
    func resetAll() {
        settings.reset()
        withAnimation(.easeInOut(duration: 0.35)) { stage = .welcome }
    }
}
