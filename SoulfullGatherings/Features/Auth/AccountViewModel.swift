//
//  AccountViewModel.swift
//  Soulfull Gatherings
//
//  Drives the create-account / sign-in form: field state, validation, and the
//  call into AuthManager plus profile sync (push local onboarding answers up on
//  create; hydrate local settings from the profile on sign-in).
//

import AuthenticationServices
@preconcurrency import Supabase
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

    /// The cross-device confirmation watch is **not** here — it lives on
    /// `AuthManager`, which outlives this sheet. See
    /// `AuthManager.beginConfirmationWatch()`.
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

    /// Opens on the code panel for a confirmation started before this sheet
    /// was: it was closed and reopened, or the app relaunched in between.
    /// See `AuthManager.confirmationToResume`.
    func resumeConfirmation(for address: String) {
        email = address
        errorMessage = nil
        resendMessage = nil
        awaitingConfirmation = true
    }

    /// "Use a different sign-in". Clears what the panel was showing, so a
    /// "that code didn't work" doesn't follow them onto the form.
    func leaveConfirmation() {
        awaitingConfirmation = false
        confirmationCode = ""
        errorMessage = nil
        resendMessage = nil
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
                if settings.userName.isEmpty { settings.userName = trimmedName }
                await auth.pushOnboardingAnswers()
                // With "Confirm email" on, the upgrade stays a guest session until
                // the emailed link is tapped, so hasAccount is still false here.
                if auth.hasAccount {
                    password = ""
                    Haptics.success()
                    return .signedIn
                } else {
                    awaitingConfirmation = true
                    // Started here as well as by the sheet's `onChange`: a
                    // sheet closed while this request was in flight never sees
                    // the change, and the watch is what notices a confirmation
                    // made on a laptop. Starting it twice is a no-op.
                    auth.beginConfirmationWatch()
                    Haptics.tap()
                    return .confirmationRequired
                }
            case .signIn:
                try await auth.signIn(email: trimmedEmail, password: password)
                password = ""
                await hydrateProfile(auth: auth, settings: settings)
                Haptics.success()
                return .signedIn
            }
        } catch {
            Haptics.bump()
            // Never the server's own words — see `AuthFailureCopy`. The detail
            // stays in the (release-redacted) log.
            Log.auth.error("Auth submit failed: \(error.localizedDescription)")
            errorMessage = AuthFailureCopy.message(for: error,
                                                   during: mode == .createAccount ? .createAccount : .signIn)
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
            errorMessage = AuthFailureCopy.message(for: error, during: .confirmCode)
            Log.auth.error("Email code verification failed: \(error.localizedDescription)")
            return .failed
        }
    }

    /// Sends a fresh confirmation email, then holds a cooldown matching the
    /// project's `smtp_max_frequency` (60s). Anything shorter just walks the
    /// user into a server rejection — GoTrue refuses a second mail to the same
    /// address inside that window.
    func resendCode(auth: AuthManager) async {
        guard resendCooldown == 0, !isWorking else { return }
        errorMessage = nil
        resendMessage = nil
        do {
            try await auth.resendConfirmation(to: confirmationEmail)
            resendMessage = "Sent — check your inbox again."
            Haptics.tap()
            startCooldown(60)
        } catch {
            Haptics.bump()
            errorMessage = AuthFailureCopy.message(for: error, during: .resendCode)
            Log.auth.error("Resend confirmation failed: \(error.localizedDescription)")
        }
    }

    /// Tears down only what this sheet owns. The cross-device confirmation
    /// watch belongs to `AuthManager` and must NOT be cancelled here — that is
    /// exactly the bug this replaced.
    func endCooldown() {
        cooldownTask?.cancel()
        cooldownTask = nil
    }

    private func finishConfirmation(auth: AuthManager, settings: AppSettings) async {
        auth.endConfirmationWatch()
        awaitingConfirmation = false
        confirmationCode = ""
        password = ""
        await auth.pushOnboardingAnswers()
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
    func submitApple(_ credential: AppleCredential,
                     auth: AuthManager, settings: AppSettings) async -> Outcome {
        guard !isWorking else { return .failed }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await auth.signInWithApple(credential)
            // Apple hands the name over exactly once; take it if we have nothing better.
            if let fullName = credential.fullName, !fullName.isEmpty,
               settings.userName.isEmpty { settings.userName = fullName }
            await mergeProfile(auth: auth, settings: settings)
            Haptics.success()
            return .signedIn
        } catch {
            guard !AuthFailureCopy.isUserCancellation(error) else { return .cancelled }
            Haptics.bump()
            errorMessage = AuthFailureCopy.message(for: error, during: .apple)
            Log.auth.error("Apple sign-in failed: \(error.localizedDescription)")
            return .failed
        }
    }

    /// Surfaces an error raised by the Apple button itself (before we ever reach
    /// Supabase), so cancels stay silent and real failures get a banner.
    ///
    /// Not `error.localizedDescription`: that put "The operation couldn't be
    /// completed. (com.apple.AuthenticationServices.AuthorizationError error
    /// 1000.)" in front of someone whose phone simply isn't signed in to an
    /// Apple ID.
    func reportAppleFailure(_ error: Error) {
        guard !AuthFailureCopy.isUserCancellation(error) else { return }
        Haptics.bump()
        Log.auth.error("Apple authorization failed: \(error.localizedDescription)")
        errorMessage = AuthFailureCopy.message(for: error, during: .apple)
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
            settings.avatarUrl = existing?.avatarUrl
            // A row can hold a name and no answers (members from before 0024).
            // Take the name first if the device has none, or the push below
            // writes the device's empty one over it. Apple hands a name over
            // only on the first authorization, so a returning member signing
            // in from Welcome arrives with nothing.
            if let existing, settings.userName.isEmpty, !existing.fullName.isEmpty {
                settings.userName = existing.fullName
            }
            if let existing, hasSavedAnswers {
                if !existing.fullName.isEmpty  { settings.userName  = existing.fullName }
                if !existing.bodyState.isEmpty { settings.bodyState = existing.bodyState }
                if !existing.frequency.isEmpty { settings.frequency = existing.frequency }
                if !existing.intentions.isEmpty { settings.intentions = Set(existing.intentions) }
            } else {
                await auth.pushOnboardingAnswers()
            }
        } catch {
            Log.auth.error("Profile merge failed: \(error.localizedDescription)")
        }
    }

    /// On sign-in (possibly on a fresh device), pull the saved profile down into
    /// local settings. Best-effort — a fetch failure shouldn't block sign-in.
    private func hydrateProfile(auth: AuthManager, settings: AppSettings) async {
        guard let id = auth.userID else { return }
        do {
            guard let profile = try await SupabaseService.shared.fetchProfile(id: id) else { return }
            settings.avatarUrl = profile.avatarUrl
            if !profile.fullName.isEmpty { settings.userName = profile.fullName }
            if !profile.bodyState.isEmpty { settings.bodyState = profile.bodyState }
            if !profile.frequency.isEmpty { settings.frequency = profile.frequency }
            if !profile.intentions.isEmpty { settings.intentions = Set(profile.intentions) }
        } catch {
            Log.auth.error("Profile hydrate failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Failure copy

/// The words for a failed auth call.
///
/// Never the server's own. GoTrue distinguishes "User already registered" from
/// "Invalid login credentials", which turned the banner into an
/// account-enumeration oracle: anyone could test whether a given address has
/// an account with a wellness app. So the copy only separates what is equally
/// true of every address — no connection, too many attempts, trouble at our
/// end — and everything else gets the same words per action.
enum AuthFailureCopy {

    enum Action { case createAccount, signIn, confirmCode, resendCode, apple }

    static let offline = "You're offline. Connect and try again."
    static let rateLimited = "Too many attempts — try again in a minute."
    static let unreachable = "We couldn't reach Soulfull just now. Try again in a moment."

    static func message(for error: any Error, during action: Action) -> String {
        // Offline used to read as wrong credentials, which sent people to
        // retype a password that was fine.
        if error.isOffline { return offline }
        if isRateLimited(error) { return rateLimited }
        if isTroubleAtOurEnd(error) { return unreachable }
        switch action {
        case .createAccount:
            return "We couldn't create that account. Check the address and password, then try again."
        case .signIn:
            return "That email and password didn't match. Try again."
        case .confirmCode:
            return "That code didn't work. Check it against the email, or send a new one."
        case .resendCode:
            return "Couldn't send a new code just now. Try again in a moment."
        case .apple:
            return "Sign in with Apple didn't go through. Try again, or use your email instead."
        }
    }

    /// Backing out of the Apple sheet is a normal choice, not a failure — it
    /// must not raise a banner.
    static func isUserCancellation(_ error: any Error) -> Bool {
        if let error = error as? ASAuthorizationError { return error.code == .canceled }
        return error.isCancellation
    }

    /// GoTrue limits by IP (sign-in, sign-up) or by address against
    /// `smtp_max_frequency` (resending), never by whether an account exists,
    /// so saying so gives nothing away.
    private static func isRateLimited(_ error: any Error) -> Bool {
        guard case let .api(_, code, _, response)? = error as? AuthError else { return false }
        return response.statusCode == 429
            || code == .overRequestRateLimit || code == .overEmailSendRateLimit
    }

    /// A 5xx or 408 from GoTrue, or a request that never got an answer (a
    /// timeout, a host that can't be reached; offline is caught before this).
    private static func isTroubleAtOurEnd(_ error: any Error) -> Bool {
        if case let .api(_, _, _, response)? = error as? AuthError {
            return response.statusCode >= 500 || response.statusCode == 408
        }
        return (error as NSError).domain == NSURLErrorDomain
    }
}
