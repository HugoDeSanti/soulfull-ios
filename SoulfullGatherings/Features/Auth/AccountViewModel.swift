//
//  AccountViewModel.swift
//  Soulfull Gatherings
//
//  Drives the create-account / sign-in form: field state, validation, and the
//  call into AuthManager plus profile sync (push local onboarding answers up on
//  create; hydrate local settings from the profile on sign-in).
//

import AuthenticationServices
import SwiftUI

@Observable @MainActor
final class AccountViewModel {

    enum Mode {
        case createAccount
        case signIn

        var title: String { self == .createAccount ? "Create your account" : "Welcome back" }
        /// The sheet usually arrives mid-tap, raised by `AccountGate`, so the
        /// copy has to justify the interruption and promise the tap isn't lost.
        var subtitle: String {
            self == .createAccount
                ? "Practices, reflections and reservations are saved to your account — create one and we'll pick up exactly where you were."
                : "Sign in and we'll pick up exactly where you were."
        }
        var cta: String { self == .createAccount ? "Create account" : "Sign in" }
    }

    /// Result of a submit attempt, so the view knows whether to dismiss, show an
    /// error, or switch to the "check your email" panel.
    enum Outcome { case signedIn, confirmationRequired, cancelled, failed }

    var mode: Mode
    var fullName = ""
    var email = ""
    var password = ""
    var isWorking = false
    var errorMessage: String?
    /// Set when account creation succeeded but the user must confirm their email
    /// (Supabase "Confirm email" is on) before the session becomes permanent.
    var awaitingConfirmation = false

    /// The code from the confirmation email. Typing it in is the path that works
    /// from *any* device — the emailed link only completes on the iPhone that
    /// signed up.
    ///
    /// Length is deliberately **not** pinned to six: it's the project's
    /// `mailer_otp_length` (6 on the live project as of 2026-09-05; the dashboard
    /// allows 6–10), which the client can't read. Digits only, and the server has
    /// the last word on whether the code is right.
    var confirmationCode = "" {
        didSet {
            let digits = String(confirmationCode.filter(\.isNumber).prefix(10))
            if digits != confirmationCode { confirmationCode = digits }
        }
    }

    /// Transient note under the code field after a successful resend.
    var resendMessage: String?

    /// Seconds left before another code can be requested (0 = ready).
    private(set) var resendCooldown = 0

    /// Owned by the view model rather than the view, so dismissing the sheet
    /// mid-flight doesn't cancel the profile write that follows a confirmation.
    private var watchTask: Task<Void, Never>?
    private var cooldownTask: Task<Void, Never>?

    /// The address a confirmation link was sent to (shown on the confirm panel).
    var confirmationEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Six is Supabase's minimum OTP length, so anything shorter can't be a code.
    var canConfirm: Bool { !isWorking && confirmationCode.count >= 6 }

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

    // MARK: - Email confirmation

    /// Verifies the code the user typed. Works wherever they read the email.
    func confirmCode(auth: AuthManager, settings: AppSettings) async -> Outcome {
        guard canConfirm else { return .failed }
        isWorking = true
        errorMessage = nil
        resendMessage = nil
        defer { isWorking = false }

        do {
            try await auth.confirmEmail(code: confirmationCode, email: confirmationEmail)
            await finishConfirmation(auth: auth, settings: settings)
            return .signedIn
        } catch {
            Haptics.bump()
            errorMessage = "That code didn't work. Check it against the email, or send a new one."
            Log.auth.error("Email code verification failed: \(error.localizedDescription)")
            return .failed
        }
    }

    /// Sends a fresh confirmation email, then holds a short cooldown so the
    /// button can't be leaned on (Supabase rate-limits these server-side).
    func resendCode(auth: AuthManager) async {
        guard resendCooldown == 0, !isWorking else { return }
        errorMessage = nil
        resendMessage = nil
        do {
            try await auth.resendConfirmation(to: confirmationEmail)
            resendMessage = "Sent — check your inbox again."
            Haptics.tap()
            startCooldown(30)
        } catch {
            Haptics.bump()
            errorMessage = "Couldn't send a new code just now. Try again in a moment."
            Log.auth.error("Resend confirmation failed: \(error.localizedDescription)")
        }
    }

    /// Watches for a confirmation completed *somewhere else*: opening the link
    /// on a laptop confirms the address server-side, and nothing tells this
    /// device — so ask, gently, while the panel is up.
    func beginConfirmationWatch(auth: AuthManager, settings: AppSettings) {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            for _ in 0..<60 {                       // ~5 minutes, then stop asking
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.awaitingConfirmation else { return }
                if await self.detectConfirmation(auth: auth) {
                    await self.finishConfirmation(auth: auth, settings: settings)
                    return
                }
            }
        }
    }

    func endConfirmationWatch() {
        watchTask?.cancel()
        watchTask = nil
        cooldownTask?.cancel()
        cooldownTask = nil
    }

    private func detectConfirmation(auth: AuthManager) async -> Bool {
        // Usual case: the guest session is still live, so re-read the user.
        if auth.userID != nil { return await auth.refreshConfirmationState() }
        // signUp fallback (no anonymous session to upgrade): there is no session
        // at all until the address is confirmed, so the only way to notice is to
        // try the credentials the user just gave us.
        guard !password.isEmpty else { return false }
        do {
            try await auth.signIn(email: confirmationEmail, password: password)
            return auth.hasAccount
        } catch {
            return false
        }
    }

    private func finishConfirmation(auth: AuthManager, settings: AppSettings) async {
        endConfirmationWatch()
        awaitingConfirmation = false
        confirmationCode = ""
        // The anonymous-upgrade path already wrote the row at create time; the
        // signUp fallback had no session then, so write it now.
        try? await pushProfile(auth: auth, settings: settings)
        Haptics.success()
    }

    private func startCooldown(_ seconds: Int) {
        cooldownTask?.cancel()
        resendCooldown = seconds
        cooldownTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.resendCooldown > 0 else { return }
                self.resendCooldown -= 1
            }
        }
    }

    // MARK: - Sign in with Apple

    /// Finishes an Apple authorization: exchanges the identity token for a
    /// Supabase session, then reconciles the profile.
    func submitApple(idToken: String, nonce: String, fullName: String?,
                     auth: AuthManager, settings: AppSettings) async -> Outcome {
        guard !isWorking else { return .failed }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await auth.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
            // Apple hands the name over exactly once; take it if we have nothing better.
            if let fullName, !fullName.isEmpty, settings.userName.isEmpty { settings.userName = fullName }
            await mergeProfile(auth: auth, settings: settings)
            Haptics.success()
            return .signedIn
        } catch {
            guard !Self.isUserCancellation(error) else { return .cancelled }
            Haptics.bump()
            errorMessage = AppError.authFailure(error).localizedDescription
            Log.auth.error("Apple sign-in failed: \(error.localizedDescription)")
            return .failed
        }
    }

    /// Surfaces an error raised by the Apple button itself (before we ever reach
    /// Supabase), so cancels stay silent and real failures get a banner.
    func reportAppleFailure(_ error: Error) {
        guard !Self.isUserCancellation(error) else { return }
        Haptics.bump()
        errorMessage = error.localizedDescription
    }

    /// Backing out of the Apple sheet is a normal choice, not a failure — it
    /// must not raise a red banner.
    private static func isUserCancellation(_ error: Error) -> Bool {
        if let error = error as? ASAuthorizationError { return error.code == .canceled }
        return error is CancellationError
    }

    /// An Apple sign-in is indistinguishable from the token alone: the identity
    /// may be brand new or returning. So look at the server row first — if it
    /// already carries answers this is a returning account and the device
    /// hydrates from it; otherwise it's a new one and the device's onboarding
    /// answers go up. Best-effort: a profile failure must not undo a valid session.
    private func mergeProfile(auth: AuthManager, settings: AppSettings) async {
        guard let id = auth.userID else { return }
        do {
            let existing = try await SupabaseService.shared.fetchProfile(id: id)
            let hasSavedAnswers = existing.map { !$0.intentions.isEmpty || !$0.bodyState.isEmpty } ?? false
            if let existing, hasSavedAnswers {
                if !existing.fullName.isEmpty  { settings.userName  = existing.fullName }
                if !existing.bodyState.isEmpty { settings.bodyState = existing.bodyState }
                if !existing.frequency.isEmpty { settings.frequency = existing.frequency }
                if !existing.intentions.isEmpty { settings.intentions = Set(existing.intentions) }
            } else {
                try await SupabaseService.shared.upsertProfile(
                    Profile(
                        id: id,
                        email: auth.email ?? existing?.email ?? "",
                        fullName: settings.userName,
                        intentions: settings.intentions.sorted(),
                        bodyState: settings.bodyState,
                        frequency: settings.frequency,
                        stripeCustomerId: nil
                    )
                )
            }
        } catch {
            Log.auth.error("Profile merge failed: \(error.localizedDescription)")
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
