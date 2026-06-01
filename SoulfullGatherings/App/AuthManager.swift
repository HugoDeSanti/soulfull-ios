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

    /// Restores an existing session or creates an anonymous one.
    /// Called once from `AppState.initializeAuth()` at launch.
    func initialize() async {
        do {
            let session = try await supabase.auth.session
            apply(session.user)
            state = .authenticated
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
    /// upgrade only completes once the user verifies the email. Keep it disabled
    /// during development, or handle the confirmation redirect in-app.
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
        } else {
            _ = try await supabase.auth.signUp(email: email, password: password, data: metadata)
        }
        apply(supabase.auth.currentUser)
    }

    /// Signs in to an existing permanent account.
    func signIn(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(email: email, password: password)
        apply(session.user)
    }

    /// Completes an email-confirmation / magic-link deep link. When the user
    /// taps the link in their email, the app opens at `soulfull://auth-callback?code=…`;
    /// the SDK exchanges the PKCE code for a confirmed session. After this the
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
            print("[AuthManager] Auth deep link failed: \(error)")
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
            print("[AuthManager] Sign-out failed: \(error)")
        }
        await SupabaseService.shared.invalidateCache()
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
            print("[AuthManager] Anonymous sign-in failed: \(error)")
        }
    }

    /// Mirrors the current user's identity into the observable properties.
    /// A present user means a live session, so reflect that in `state` too —
    /// otherwise a successful createAccount/signIn after a failed launch-time
    /// anonymous sign-in would leave `state == .failed` and `hasAccount == false`.
    private func apply(_ user: User?) {
        isAnonymous = user?.isAnonymous ?? true
        let mail = user?.email
        email = (mail?.isEmpty ?? true) ? nil : mail
        if user != nil { state = .authenticated }
    }
}
