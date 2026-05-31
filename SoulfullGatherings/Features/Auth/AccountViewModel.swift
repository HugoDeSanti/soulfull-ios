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

    var mode: Mode
    var fullName = ""
    var email = ""
    var password = ""
    var isWorking = false
    var errorMessage: String?

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

    /// Performs the auth call + profile sync. Returns `true` on success so the
    /// view can dismiss.
    func submit(auth: AuthManager, settings: AppSettings) async -> Bool {
        guard canSubmit else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            switch mode {
            case .createAccount:
                try await auth.createAccount(email: trimmedEmail, password: password, fullName: trimmedName)
                try await pushProfile(auth: auth, settings: settings)
            case .signIn:
                try await auth.signIn(email: trimmedEmail, password: password)
                await hydrateProfile(auth: auth, settings: settings)
            }
            Haptics.success()
            return true
        } catch {
            Haptics.bump()
            errorMessage = error.localizedDescription
            return false
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
            print("[AccountViewModel] Profile hydrate failed: \(error)")
        }
    }
}
