//
//  AccountViewModel.swift
//  Soulfull Gatherings
//
//  Drives the create-account / sign-in form: field state, validation, and the
//  call into AuthManager plus profile sync (push local onboarding answers up on
//  create; hydrate local settings from the profile on sign-in).
//

import SwiftUI

@Observable @MainActor
final class AccountViewModel {

    enum Mode {
        case createAccount
        case signIn

        var title: String { self == .createAccount ? "Create your account" : "Welcome back" }
        var subtitle: String {
            self == .createAccount
                ? "Save your space, reserve retreats, and keep your practice across devices."
                : "Sign in to pick up right where you left off."
        }
        var cta: String { self == .createAccount ? "Create account" : "Sign in" }
    }

    /// Result of a submit attempt, so the view knows whether to dismiss, show an
    /// error, or switch to the "check your email" panel.
    enum Outcome { case signedIn, confirmationRequired, failed }

    var mode: Mode
    var fullName = ""
    var email = ""
    var password = ""
    var isWorking = false
    var errorMessage: String?
    /// Set when account creation succeeded but the user must confirm their email
    /// (Supabase "Confirm email" is on) before the session becomes permanent.
    var awaitingConfirmation = false

    /// The address a confirmation link was sent to (shown on the confirm panel).
    var confirmationEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(mode: Mode = .createAccount) {
        self.mode = mode
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { fullName.trimmingCharacters(in: .whitespaces) }

    var canSubmit: Bool {
        guard !isWorking else { return false }
        let emailLooksValid = trimmedEmail.contains("@") && trimmedEmail.contains(".")
        guard emailLooksValid, password.count >= 8 else { return false }
        return mode == .signIn || !trimmedName.isEmpty
    }

    func toggleMode() {
        Haptics.tap()
        mode = (mode == .createAccount) ? .signIn : .createAccount
        errorMessage = nil
    }

    /// Performs the auth call + profile sync.
    /// - `.signedIn`: dismiss (session is live).
    /// - `.confirmationRequired`: account created but email must be confirmed —
    ///   show the "check your email" panel; the deep link completes it.
    /// - `.failed`: `errorMessage` is set.
    func submit(auth: AuthManager, settings: AppSettings) async -> Outcome {
        guard canSubmit else { return .failed }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            switch mode {
            case .createAccount:
                try await auth.createAccount(email: trimmedEmail, password: password, fullName: trimmedName)
                try await pushProfile(auth: auth, settings: settings)
                // With "Confirm email" on, the upgrade stays a guest session until
                // the emailed link is tapped, so hasAccount is still false here.
                if auth.hasAccount {
                    Haptics.success()
                    return .signedIn
                } else {
                    awaitingConfirmation = true
                    Haptics.tap()
                    return .confirmationRequired
                }
            case .signIn:
                try await auth.signIn(email: trimmedEmail, password: password)
                await hydrateProfile(auth: auth, settings: settings)
                Haptics.success()
                return .signedIn
            }
        } catch {
            Haptics.bump()
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    /// On account creation, push the device's onboarding answers up so the new
    /// account starts populated.
    private func pushProfile(auth: AuthManager, settings: AppSettings) async throws {
        guard let id = auth.userID else { return }
        if settings.userName.isEmpty { settings.userName = trimmedName }
        let profile = Profile(
            id: id,
            email: trimmedEmail,
            fullName: settings.userName.isEmpty ? trimmedName : settings.userName,
            intentions: settings.intentions.sorted(),
            bodyState: settings.bodyState,
            frequency: settings.frequency,
            stripeCustomerId: nil
        )
        try await SupabaseService.shared.upsertProfile(profile)
    }

    /// On sign-in (possibly on a fresh device), pull the saved profile down into
    /// local settings. Best-effort — a fetch failure shouldn't block sign-in.
    private func hydrateProfile(auth: AuthManager, settings: AppSettings) async {
        guard let id = auth.userID else { return }
        do {
            guard let profile = try await SupabaseService.shared.fetchProfile(id: id) else { return }
            if !profile.fullName.isEmpty { settings.userName = profile.fullName }
            if !profile.bodyState.isEmpty { settings.bodyState = profile.bodyState }
            if !profile.frequency.isEmpty { settings.frequency = profile.frequency }
            if !profile.intentions.isEmpty { settings.intentions = Set(profile.intentions) }
        } catch {
            Log.auth.error("Profile hydrate failed: \(error.localizedDescription)")
        }
    }
}
