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
    /// Held so sign-out and deletion can clear the answers that describe a
    /// person, and so a confirmation landing after the account sheet closed can
    /// still push them to the new profile.
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
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

    // MARK: - Cross-device confirmation watch

    /// Polls for a confirmation completed somewhere else, and pushes the
    /// device's onboarding answers once it lands.
    ///
    /// This lives here, not on `AccountViewModel`, because it has to outlive
    /// the account sheet. The view model owned it and documented itself as
    /// doing so ("dismissing the sheet mid-flight doesn't cancel the profile
    /// write") — but `AccountView.onDisappear` cancelled it and the `@State`
    /// view model was deallocated with the sheet anyway. Someone who signed
    /// up, swiped the sheet away and confirmed on their laptop saw nothing
    /// happen until the app was relaunched.
    ///
    /// `AuthManager` is app-lifetime, so the watch now survives that, and the
    /// sheet's `onChange(of: auth.hasAccount)` closes itself when it fires.
    private var confirmationWatch: Task<Void, Never>?

    func beginConfirmationWatch() {
        guard confirmationWatch == nil, !hasAccount else { return }
        confirmationWatch = Task { [weak self] in
            // Backoff rather than a fixed 5s: this used to hammer the auth
            // endpoint 60 times per sign-up. Roughly 5s → 60s over ~10 minutes.
            var delay = Duration.seconds(5)
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(60))
                guard !Task.isCancelled, let self else { return }
                // `hasAccount` first: the confirmation may have completed by a
                // route this loop didn't drive — the emailed link deep-linking
                // back into the app, or the code panel. Returning early on that
                // (as an earlier version did) skipped the profile push
                // entirely, which is the only reason this watch exists.
                var confirmed = self.hasAccount
                if !confirmed { confirmed = await self.refreshConfirmationState() }
                if confirmed {
                    await self.pushOnboardingAnswers()
                    return
                }
            }
        }
    }

    func endConfirmationWatch() {
        confirmationWatch?.cancel()
        confirmationWatch = nil
    }

    /// Writes the device's onboarding answers onto the signed-in profile.
    /// Best-effort and idempotent — a failure must never undo a valid session.
    ///
    /// Owned here rather than by `AccountViewModel` so the watch above can run
    /// it after the sheet is gone. `email` is deliberately absent: it is
    /// server-owned (mirrored from `auth.users` by 0009) and was previously
    /// client-writable, which let a member address their Stripe customer record
    /// at someone else's address.
    func pushOnboardingAnswers() async {
        guard let id = userID, hasAccount else { return }
        do {
            try await SupabaseService.shared.upsertProfile(
                Profile(
                    id: id,
                    email: email ?? "",
                    fullName: settings.userName,
                    intentions: settings.intentions.sorted(),
                    bodyState: settings.bodyState,
                    frequency: settings.frequency,
                    stripeCustomerId: nil
                )
            )
        } catch {
            Log.auth.error("Profile push failed: \(error.localizedDescription)")
        }
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
    func signInWithApple(_ credential: AppleCredential) async throws {
        let session = try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple,
                                                  idToken: credential.idToken,
                                                  nonce: credential.nonce)
        )
        // Apple returns the user's name only on the *first* authorization ever
        // granted to this app, so persist it the one time we see it.
        if let fullName = credential.fullName, !fullName.isEmpty,
           session.user.userMetadata["full_name"] == nil {
            _ = try? await supabase.auth.update(user: UserAttributes(data: ["full_name": .string(fullName)]))
        }
        apply(supabase.auth.currentUser)
        // Detached from the sign-in on purpose — see `storeAppleRefreshToken`.
        let code = credential.authorizationCode
        Task { await self.storeAppleRefreshToken(code) }
    }

    /// Hands Apple's single-use authorization code to the `store-apple-token`
    /// Edge Function, which exchanges it with Apple for a refresh token and
    /// keeps it where only the service role can read it.
    ///
    /// That token is what `delete-account` feeds to Apple's `/auth/revoke`.
    /// **App Store Guideline 5.1.1(v) requires that revocation** of any app
    /// offering both Sign in with Apple and account deletion — deleting the
    /// Supabase user alone leaves the app listed under Settings → Apple ID →
    /// Sign in with Apple, which is precisely what a reviewer checks. So this
    /// is compliance work, not housekeeping.
    ///
    /// It is nonetheless **best-effort, never throws, and deliberately runs
    /// off the sign-in's own task**: the member asked to sign in, and making
    /// them watch a spinner while a *follow-up* call to Apple round-trips is a
    /// bad trade — on a poor connection the invoke can sit there for the
    /// URLSession timeout, long after the session itself is live. Apple mints a
    /// fresh code on *every* authorization, so a miss here is repaired by the
    /// next sign-in rather than being permanent; the cost is one account that
    /// deletes without revoking, which `delete-account` also logs.
    ///
    /// The theoretical race — delete the account before the exchange lands —
    /// needs the member to cross into the You tab, tap Delete account and
    /// confirm a dialog inside the round-trip, which is not a real sequence.
    /// Don't make this blocking to close it.
    private func storeAppleRefreshToken(_ authorizationCode: String?) async {
        guard let authorizationCode, !authorizationCode.isEmpty else {
            Log.auth.error("Apple returned no authorization code; account deletion won't be able to revoke this grant.")
            return
        }
        struct Body: Encodable {
            let authorizationCode: String
            enum CodingKeys: String, CodingKey { case authorizationCode = "authorization_code" }
        }
        struct Result: Decodable { let stored: Bool }
        do {
            let _: Result = try await supabase.functions.invoke(
                "store-apple-token",
                options: FunctionInvokeOptions(body: Body(authorizationCode: authorizationCode))
            )
        } catch {
            Log.auth.error("Storing the Apple refresh token failed: \(error.localizedDescription)")
        }
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
            // The account just became permanent by a route the account sheet
            // isn't driving, so nothing else would carry the device's
            // onboarding answers up. No-ops if they're already there.
            await pushOnboardingAnswers()
            endConfirmationWatch()
            return true
        } catch {
            // Deliberately does NOT touch `state`.
            //
            // `soulfull://` is an unclaimed custom scheme: any installed app, or
            // a link on any web page, can open `soulfull://auth-callback?code=x`.
            // Setting `.failed` here let an external party flip
            // `needsRetry` and park the ConnectionBanner over every tab of a
            // perfectly healthy session. A code that doesn't exchange is a
            // property of the link, not of the session — the PKCE verifier is
            // in this device's Keychain and an attacker's code simply won't
            // match it, which is the flow working correctly.
            Log.auth.error("Auth deep link failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Signs out of a permanent account and returns to a fresh anonymous guest
    /// session so the rest of the app keeps working.
    func signOut() async {
        // While the session is still valid: this phone stops being theirs.
        await PushRegistrar.shared.forgetDevice()
        do {
            try await supabase.auth.signOut()
        } catch {
            Log.auth.error("Sign-out failed: \(error.localizedDescription)")
        }
        await SupabaseService.shared.invalidateCache()
        endConfirmationWatch()
        pendingConfirmation = nil
        // The answers describe the person who is leaving, not this phone. Left
        // in place they were shown to whoever signed in next AND uploaded to
        // their profile row by AccountViewModel.mergeProfile — see
        // AppSettings.clearPersonalAnswers().
        settings.clearPersonalAnswers()
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
        endConfirmationWatch()
        // Everything this member kept on the device goes with it — journal
        // reflections and trip checklists. The confirmation dialog promises to
        // delete "saved data", and until this call it didn't: the server row
        // went and the writing stayed behind. Purge before the sign-out below
        // switches the scope out from under us.
        LocalUserStore.shared.purgeCurrentScope()
        PracticeProgressStore.shared.clear()
        ProgramStore.shared.clear()
        // A "Day 3 is open" nudge for a program belonging to an account that no
        // longer exists is the kind of thing people delete an app over.
        ProgramNotifications.cancelAll()
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

        // Device-local private data is namespaced per member, so tell the store
        // whose data is now in scope. It hands a guest's writing forward when
        // that guest becomes a member, and returns true only when the identity
        // actually moved — this runs on every confirmation poll.
        if !isAnonymous {
            // A member arrived (sign-in, or a guest upgraded in place): file
            // this device under them if they already allow notifications.
            Task { await PushRegistrar.shared.syncIfAuthorized(isMember: true) }
        }
        if LocalUserStore.shared.adopt(userID: user?.id, isAnonymous: isAnonymous) {
            RetreatTripStore.shared.reload()
            // Server-side practice history belongs to the previous member;
            // drop it so their continue card can't flash up for someone else.
            PracticeProgressStore.shared.clear()
            // Same for program enrolment — and the scheduled nudges with it.
            ProgramStore.shared.clear()
            ProgramNotifications.cancelAll()
        }
    }
}
