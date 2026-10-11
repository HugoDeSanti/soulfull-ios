//
//  AccountViewModel.swift
//  Soulfull Gatherings
//
//  Drives the create-account / sign-in form: field state, validation, and the
//  call into AuthManager plus profile sync (push local onboarding answers up on
//  create; hydrate local settings from the profile on sign-in). Also the
//  forgot-password steps: a code by email, then a new password.
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
                ? "Your practice history, streaks and digital retreats are saved to your account — create one and we'll pick up exactly where you were."
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
            let digits = Self.codeDigits(confirmationCode)
            if digits != confirmationCode { confirmationCode = digits }
        }
    }

    /// Pasted codes arrive with spaces and dashes. Digits only, up to ten,
    /// the most `mailer_otp_length` allows.
    private static func codeDigits(_ text: String) -> String {
        String(text.filter(\.isNumber).prefix(10))
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

    // MARK: - Forgot password

    /// Where someone who forgot their password is. `nil` is the form.
    enum PasswordResetStep: Equatable {
        /// Asking which address the code should go to.
        case request
        /// A code is on its way: enter it with a new password.
        case newPassword
    }

    /// What the reset steps call. Closures, so the steps can be tested
    /// without Supabase (`SoulfullTests/PasswordResetFlowTests`); the sheet
    /// builds it from `AuthManager` with `resetBackend(auth:settings:)`.
    struct PasswordResetBackend {
        var sendCode: @MainActor (_ email: String) async throws -> Void
        var verifyCode: @MainActor (_ code: String, _ email: String) async throws -> Void
        var setPassword: @MainActor (_ password: String) async throws -> Void
        /// Runs once the code has signed them in, to bring the profile down
        /// as a sign-in does.
        var signedIn: @MainActor () async -> Void
    }

    var passwordReset: PasswordResetStep?

    var resetCode = "" {
        didSet {
            let digits = Self.codeDigits(resetCode)
            if digits != resetCode { resetCode = digits }
        }
    }

    var newPassword = ""

    /// The code has signed them in and only the password is left. A code is
    /// single-use, so a retry after a refused password mustn't send it again.
    private(set) var resetCodeAccepted = false

    var canSendResetCode: Bool {
        !isWorking && trimmedEmail.contains("@") && trimmedEmail.contains(".")
    }

    /// The rule `canSubmit` enforces on create: the server's own minimum
    /// (`password_min_length`) is lower.
    var canSetNewPassword: Bool {
        !isWorking && (resetCodeAccepted || resetCode.count >= 6) && newPassword.count >= 8
    }

    func resetBackend(auth: AuthManager, settings: AppSettings) -> PasswordResetBackend {
        PasswordResetBackend(
            sendCode: { try await auth.requestPasswordReset(email: $0) },
            verifyCode: { try await auth.verifyPasswordResetCode($0, email: $1) },
            setPassword: { try await auth.setNewPassword($0) },
            signedIn: { [weak self] in await self?.hydrateProfile(auth: auth, settings: settings) }
        )
    }

    /// "Forgot password?" on the sign-in form. The address carries over; the
    /// password that didn't work doesn't.
    func beginPasswordReset() {
        password = ""
        errorMessage = nil
        resendMessage = nil
        passwordReset = .request
    }

    /// "Back to sign in". The address carries back.
    func leavePasswordReset() {
        passwordReset = nil
        mode = .signIn
        resetCode = ""
        newPassword = ""
        resetCodeAccepted = false
        errorMessage = nil
        resendMessage = nil
    }

    /// Sends the code and moves on to it. A success says nothing about whether
    /// the address has an account (see `AuthManager.requestPasswordReset`).
    func sendResetCode(_ backend: PasswordResetBackend) async {
        guard canSendResetCode else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await backend.sendCode(trimmedEmail)
            email = trimmedEmail
            passwordReset = .newPassword
            Haptics.tap()
            // GoTrue sends one email per address a minute (`smtp_max_frequency`).
            startCooldown(60)
        } catch {
            Haptics.bump()
            errorMessage = AuthFailureCopy.message(for: error, during: .requestReset)
            Log.auth.error("Password reset request failed: \(error.localizedDescription)")
        }
    }

    /// A new code replaces the old one on the server, so the field clears.
    func resendResetCode(_ backend: PasswordResetBackend) async {
        guard resendCooldown == 0, !isWorking, !resetCodeAccepted else { return }
        errorMessage = nil
        resendMessage = nil
        do {
            try await backend.sendCode(trimmedEmail)
            resetCode = ""
            resendMessage = "Sent — check your inbox again."
            Haptics.tap()
            startCooldown(60)
        } catch {
            Haptics.bump()
            errorMessage = AuthFailureCopy.message(for: error, during: .resendCode)
            Log.auth.error("Password reset resend failed: \(error.localizedDescription)")
        }
    }

    /// Spends the code (once), then sets the password.
    /// - `.signedIn`: done. Dismiss.
    /// - `.failed`: `errorMessage` says which half didn't go through. After
    ///   the code is accepted they're signed in, and only the password is left.
    func setNewPassword(_ backend: PasswordResetBackend) async -> Outcome {
        guard canSetNewPassword else { return .failed }
        isWorking = true
        errorMessage = nil
        resendMessage = nil
        defer { isWorking = false }

        if !resetCodeAccepted {
            do {
                try await backend.verifyCode(resetCode, email)
            } catch {
                Haptics.bump()
                errorMessage = AuthFailureCopy.message(for: error, during: .confirmCode)
                Log.auth.error("Password reset code failed: \(error.localizedDescription)")
                return .failed
            }
            resetCodeAccepted = true
            resetCode = ""
            // Signed in from here, whatever happens to the password: closing
            // the sheet now must land like any other sign-in.
            await backend.signedIn()
        }

        do {
            try await backend.setPassword(newPassword)
        } catch where AuthFailureCopy.isSamePassword(error) {
            // The account already has this password. It works, and now they
            // know it, which is all they came for.
        } catch {
            Haptics.bump()
            errorMessage = AuthFailureCopy.message(for: error, during: .newPassword)
            Log.auth.error("Setting the new password failed: \(error.localizedDescription)")
            return .failed
        }

        newPassword = ""
        Haptics.success()
        return .signedIn
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
            // Also gives a row that lost its name the sign-up name back, so
            // Welcome's sign-in greets them instead of re-running onboarding.
            await auth.reconcileName(with: profile)
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

    enum Action { case createAccount, signIn, confirmCode, resendCode, apple, requestReset, newPassword }

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
            // The second sentence is true of every address, so it reveals
            // nothing — but it rescues someone typing an existing account's
            // credentials into this form (App Review's demo account included).
            return "We couldn't create that account. Check the address and password, then try again. Already have an account? Sign in below."
        case .signIn:
            return "That email and password didn't match. Try again."
        case .confirmCode:
            return "That code didn't work. Check it against the email, or send a new one."
        case .resendCode:
            return "Couldn't send a new code just now. Try again in a moment."
        case .apple:
            return "Sign in with Apple didn't go through. Try again, or use your email instead."
        case .requestReset:
            // A malformed address; one without an account succeeds.
            return "We couldn't send a code to that address. Check it and try again."
        case .newPassword:
            // Only someone who has just proved the address is theirs gets
            // here, so naming the problem gives nothing away.
            return errorCode(of: error) == .weakPassword
                ? "Choose a stronger password. A longer one is the easiest fix."
                : "We couldn't save that password. Try again."
        }
    }

    /// GoTrue refuses a "new" password that is already the account's.
    static func isSamePassword(_ error: any Error) -> Bool {
        errorCode(of: error) == .samePassword
    }

    private static func errorCode(of error: any Error) -> ErrorCode? {
        (error as? AuthError)?.errorCode
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
