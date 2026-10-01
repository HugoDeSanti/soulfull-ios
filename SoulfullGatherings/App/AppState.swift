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
        let settings = AppSettings()
        self.settings = settings
        // AuthManager holds the settings so sign-out / deletion can clear the
        // answers that describe a person, and so a confirmation that lands
        // after the account sheet closed can still push them.
        auth = AuthManager(settings: settings)
    }

    /// Called once at launch from `SoulfullGatheringsApp.body` via `.task`.
    /// Establishes auth then routes to the correct stage.
    ///
    /// Reaching `.main` needs only the onboarding answers — **not** an account.
    /// Browsing is open to an anonymous guest; the account is asked for at the
    /// moment the user reaches for a practice, via `AccountGate`. A hard gate
    /// here would put the app in scope for Guideline 5.1.1(i).
    func initializeAuth() async {
        await auth.initialize()
        let next: Stage = settings.hasOnboarded ? .main : .welcome
        withAnimation(.easeInOut(duration: 0.45)) { stage = next }
    }

    func beginOnboarding() {
        withAnimation(.easeInOut(duration: 0.35)) { stage = .onboarding }
    }

    /// After Welcome's "I already have an account" sheet closes. A sign-in has
    /// already pulled the profile down by then: the sheet stays up until the
    /// hydration that follows it is done (see `AccountView.trySubmit`).
    ///
    /// That button used to call `beginOnboarding()`, exactly like Begin, so a
    /// returning member answered four questions and landed as a guest.
    func returnFromWelcomeSignIn() {
        switch Self.stageAfterWelcomeSignIn(hasAccount: auth.hasAccount, userName: settings.userName) {
        case .main?:
            // Not `finishOnboarding()`: the sign-in has just given its own
            // success haptic, and there are no new answers to push.
            settings.hasOnboarded = true
            withAnimation(.easeInOut(duration: 0.45)) { stage = .main }
        case .onboarding?:
            beginOnboarding()
        default:
            break
        }
    }

    /// Where a sign-in from Welcome leads.
    /// - `nil`: the sheet closed without a sign-in, so Welcome stays. It is an
    ///   offer, never a gate (Guideline 5.1.1).
    /// - `.main`: the profile brought a name down, and the answers with it,
    ///   so Home can greet them straight away.
    /// - `.onboarding`: signed in, but the profile had no name to greet them
    ///   by (rows from before 0024 can be empty), so ask.
    static func stageAfterWelcomeSignIn(hasAccount: Bool, userName: String) -> Stage? {
        guard hasAccount else { return nil }
        return userName.trimmingCharacters(in: .whitespaces).isEmpty ? .onboarding : .main
    }

    func finishOnboardingSkipping(name: String) {
        settings.userName = name.trimmingCharacters(in: .whitespaces)
        finishOnboarding()
    }

    func finishOnboarding() {
        settings.hasOnboarded = true
        // A member who signed in from Welcome answered these with the account
        // already in place, after every other push (create, confirm, Apple's
        // merge) had run. A guest's answers go up when they make an account.
        if auth.hasAccount {
            Task { await auth.pushOnboardingAnswers() }
        }
        Haptics.success()
        withAnimation(.easeInOut(duration: 0.45)) { stage = .main }
    }

    /// Used by the in-app "reset onboarding" Profile action (handy during dev).
    func resetAll() {
        settings.reset()
        withAnimation(.easeInOut(duration: 0.35)) { stage = .welcome }
    }
}
