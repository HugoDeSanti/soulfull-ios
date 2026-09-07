import SwiftUI
@preconcurrency import Supabase

/// Manages Supabase Auth. Opens an anonymous session on first launch and
/// restores it on subsequent launches, and lets the user upgrade that guest
/// session into a permanent email/password account (preserving their user id
/// and any data). Injected into the environment alongside AppState so any view
/// can gate on `auth.isAuthenticated` / `auth.hasAccount`.
@Observable @MainActor
final class AuthManager {

    enum State: Equatable {
        case initializing
        case authenticated
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.initializing, .initializing):   return true
            case (.authenticated, .authenticated): return true
            case (.failed(let a), .failed(let b)): return a == b
            default:                               return false
            }
        }
    }

    private(set) var state: State = .initializing

    /// True while the active session is an anonymous guest (the default at launch).
    private(set) var isAnonymous = true

    /// How a still-pending email confirmation was started. It decides which OTP
    /// type verifies the code the user types in: upgrading a guest is an
    /// *email change* on the existing user, while the no-session fallback is a
    /// plain *signup*. Cleared once the account is permanent.
    enum PendingConfirmation { case signup, emailChange }
    private(set) var pendingConfirmation: PendingConfirmation?

    /// Email of the signed-in permanent account, if any.
    private(set) var email: String?

    var isAuthenticated: Bool { state == .authenticated }

    /// A permanent (non-anonymous) account is signed in. Gate Reserve / paid
    /// flows on this — not on `isAuthenticated`, which is true for guests too.
    var hasAccount: Bool { isAuthenticated && !isAnonymous }

    /// Current user id — used to key the `profiles` row.
    var userID: UUID? { supabase.auth.currentUser?.id }

    private let supabase: SupabaseClient

    init() {
        supabase = SupabaseService.shared.client
    }

    /// True when launch-time auth failed and nothing has recovered it. The UI
    /// surfaces this as a retry banner — before, a failed anonymous sign-in was
    /// completely silent and the user only discovered it when an action that
    /// needed a session threw a raw error at them.
    var needsRetry: Bool {
        if case .failed = state { return true }
        return false
    }

    /// User-facing reason for the current failure, if any.
    var failureMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// Re-attempt a session after a failed launch. Safe to call repeatedly.
    func retry() async {
        state = .initializing
        await initialize()
    }

    /// Restores an existing session or creates an anonymous one.
    /// Called once from `AppState.initializeAuth()` at launch.
    func initialize() async {
        do {
            let session = try await supabase.auth.session
            apply(session.user)
            state = .authenticated
            // A restored guest session can carry stale claims: the user may have
            // confirmed their email from a laptop while the app was closed, and
            // the cached JWT won't say so until it next refreshes (up to an
            // hour). Reconcile against the server in the background so
            // `hasAccount` is right without holding up launch.
            if isAnonymous {
                Task { await self.refreshConfirmationState() }
            }
        } catch {
            await signInAnonymously()
        }
    }

    // MARK: - Account creation / sign-in

    /// Creates a permanent account. If the current session is an anonymous
    /// guest (the usual case), it is *upgraded in place* so the same user id
    /// and any existing data carry over; otherwise a fresh account is created.
    ///
    /// Note: when "Confirm email" is enabled in Supabase, the anonymous→permanent
    /// upgrade only completes once the user verifies the email — by tapping the
    /// emailed link on this device (`handleDeepLink`), by typing the emailed
    /// code (`confirmEmail`), or by opening the link anywhere else and
    /// letting `refreshConfirmationState` notice.
    func createAccount(email: String, password: String, fullName: String) async throws {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)
        let metadata: [String: AnyJSON]? = trimmed.isEmpty ? nil : ["full_name": .string(trimmed)]
        // Upgrade in place only when there's a live anonymous session to upgrade.
        // If there's no session (e.g. anonymous sign-in is unavailable), fall back
        // to a fresh signUp rather than calling `update` with no session — which
        // would throw "Auth session missing".
        if supabase.auth.currentUser?.isAnonymous == true {
            _ = try await supabase.auth.update(
                user: UserAttributes(email: email, password: password, data: metadata)
            )
            pendingConfirmation = .emailChange
        } else {
            _ = try await supabase.auth.signUp(email: email, password: password, data: metadata)
            pendingConfirmation = .signup
        }
        apply(supabase.auth.currentUser)
        // Confirmation is off (or already satisfied) — nothing is pending.
        if hasAccount { pendingConfirmation = nil }
    }

    // MARK: - Email confirmation

    /// Confirms the address with the numeric code from the email. Its length is
    /// the project's `mailer_otp_length` (6 here), so nothing pins it client-side.
    ///
    /// This is the path that works **from any device**: the emailed link can
    /// only finish on the iPhone that signed up (it redirects to the
    /// `soulfull://` scheme and the PKCE verifier lives in this device's
    /// Keychain), whereas a code the user reads on a laptop and types in here
    /// verifies against the server directly and returns a real session.
    ///
    /// Which OTP type applies depends on how the account was created, and
    /// GoTrue rejects the wrong one harmlessly, so the likely type is tried
    /// first and the other is the fallback.
    func confirmEmail(code: String, email: String) async throws {
        let digits = String(code.filter(\.isNumber))
        let candidates: [EmailOTPType] = pendingConfirmation == .signup
            ? [.signup, .emailChange]
            : [.emailChange, .signup]

        var lastError: (any Error)?
        for type in candidates {
            do {
                let response = try await supabase.auth.verifyOTP(email: email, token: digits, type: type)
                apply(response.session?.user ?? response.user)
                pendingConfirmation = nil
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? AppError.unknown
    }

    /// Sends a fresh confirmation email (new code + new link).
    func resendConfirmation(to email: String) async throws {
        let candidates: [ResendEmailType] = pendingConfirmation == .signup
            ? [.signup, .emailChange]
            : [.emailChange, .signup]

        var lastError: (any Error)?
        for type in candidates {
            do {
                try await supabase.auth.resend(email: email, type: type)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? AppError.unknown
    }

    /// Re-reads the user from the server and adopts the result.
    ///
    /// Opening the emailed link on *another* device confirms the address
    /// server-side, but nothing pushes that back to this one — the local
    /// session keeps its pre-confirmation claims until it refreshes. Polling
    /// this while the confirm panel is up (and once at launch) is what makes a
    /// confirmation from a laptop land on the phone.
    ///
    /// Returns `true` once a permanent account is in place.
    @discardableResult
    func refreshConfirmationState() async -> Bool {
        do {
            // GET /user is a fresh read and doesn't rotate the refresh token,
            // so it's cheap enough to poll.
            let user = try await supabase.auth.user()
            let confirmed = !(user.email?.isEmpty ?? true) && user.emailConfirmedAt != nil
            if confirmed, supabase.auth.currentUser?.isAnonymous == true {
                // The access token still claims `is_anonymous` — rotate it so
                // RLS and the Edge Functions see the permanent account too.
                let session = try await supabase.auth.refreshSession()
                apply(session.user)
            } else {
                apply(user)
            }
            if hasAccount { pendingConfirmation = nil }
        } catch {
            Log.auth.debug("Confirmation refresh skipped: \(error.localizedDescription)")
        }
        return hasAccount
    }

    // MARK: - Sign in with Apple

    /// Signs in with Apple, using the identity token that
    /// `SignInWithAppleButton` hands back. `nonce` must be the *raw* nonce whose
    /// SHA-256 was put on the authorization request — Supabase re-hashes it and
    /// compares against the `nonce` claim inside the token.
    ///
    /// Apple is the only third-party provider the app offers.
    ///
    /// Unlike `createAccount`, this does **not** upgrade the anonymous guest in
    /// place: Supabase signs in the Apple identity as its own user and the guest
    /// session is replaced. Nothing user-visible is lost — the onboarding
    /// answers live in `AppSettings` and are pushed onto the new user's profile
    /// by `AccountViewModel`. (Preserving the guest id would need `linkIdentity`,
    /// which requires manual linking to be enabled in the Supabase dashboard.)
    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        let session = try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        // Apple returns the user's name only on the *first* authorization ever
        // granted to this app, so persist it the one time we see it.
        if let fullName, !fullName.isEmpty, session.user.userMetadata["full_name"] == nil {
            _ = try? await supabase.auth.update(user: UserAttributes(data: ["full_name": .string(fullName)]))
        }
        apply(supabase.auth.currentUser)
    }

    /// Signs in to an existing permanent account.
    func signIn(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(email: email, password: password)
        apply(session.user)
    }

    /// Completes an email-confirmation / magic-link deep link. When the user
    /// taps the link in their email *on this device*, the app opens at
    /// `soulfull://auth-callback?code=…`; the SDK exchanges the PKCE code for a
    /// confirmed session. (Opened anywhere else the address is still confirmed
    /// server-side — `confirmEmail` / `refreshConfirmationState` cover that.) After this the
    /// (previously anonymous) user is permanent — `hasAccount` becomes true.
    /// Returns true if the URL was an auth callback we handled.
    @discardableResult
    func handleDeepLink(_ url: URL) async -> Bool {
        guard url.scheme == SupabaseService.authRedirectURL.scheme else { return false }
        do {
            let session = try await supabase.auth.session(from: url)
            apply(session.user)
            return true
        } catch {
            Log.auth.error("Auth deep link failed: \(error.localizedDescription)")
            state = .failed(AppError.authFailure(error).localizedDescription)
            return false
        }
    }

    /// Signs out of a permanent account and returns to a fresh anonymous guest
    /// session so the rest of the app keeps working.
    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            Log.auth.error("Sign-out failed: \(error.localizedDescription)")
        }
        await SupabaseService.shared.invalidateCache()
        pendingConfirmation = nil
        await signInAnonymously()
    }

    /// Permanently deletes the signed-in account via the `delete-account` Edge
    /// Function (removes the Stripe customer, then deletes the auth user —
    /// cascading to `profiles` + `bookings`), then returns to a fresh guest
    /// session. Required for App Store compliance (sign-up ⇒ must offer deletion).
    func deleteAccount() async throws {
        struct DeleteResult: Decodable { let deleted: Bool }
        // The Functions client attaches the current session's JWT, so the server
        // deletes exactly this user.
        let _: DeleteResult = try await supabase.functions.invoke("delete-account")
        // The session is now invalid server-side; drop it and open a fresh
        // anonymous one so the app stays usable.
        await signOut()
    }

    // MARK: - Private

    private func signInAnonymously() async {
        do {
            let session = try await supabase.auth.signInAnonymously()
            apply(session.user)
            state = .authenticated
        } catch {
            let msg = AppError.authFailure(error).localizedDescription
            state = .failed(msg)
            Log.auth.error("Anonymous sign-in failed: \(error.localizedDescription)")
        }
    }

    /// Mirrors the current user's identity into the observable properties.
    /// A present user means a live session, so reflect that in `state` too —
    /// otherwise a successful createAccount/signIn after a failed launch-time
    /// anonymous sign-in would leave `state == .failed` and `hasAccount == false`.
    private func apply(_ user: User?) {
        let mail = user?.email
        let hasEmail = !(mail?.isEmpty ?? true)
        // A *confirmed* email address means this is no longer a guest, whatever
        // the token says: right after a cross-device confirmation the cached
        // JWT can still carry the pre-upgrade `is_anonymous` claim.
        let confirmed = hasEmail && user?.emailConfirmedAt != nil
        isAnonymous = (user?.isAnonymous ?? true) && !confirmed
        email = hasEmail ? mail : nil
        if user != nil { state = .authenticated }
    }
}
