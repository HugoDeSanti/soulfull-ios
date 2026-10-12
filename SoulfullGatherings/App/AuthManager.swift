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
        /// No session could be established. Any session already stored on the
        /// device is still there, so Retry can restore it once the network is.
        case failed(ConnectionFailure)
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

    /// The address a confirmation started this launch is waiting on. Kept here
    /// because the account sheet's view model dies with the sheet, and a guest
    /// who closed it and came back used to get a blank create form: submitting
    /// it again either hit the send rate limit or invalidated the code they
    /// already had.
    private var pendingConfirmationEmail: String?
    /// Set when someone leaves the code panel for "Use a different sign-in",
    /// so the sheet stops steering them back to it for the rest of the launch.
    private var confirmationSetAside = false

    /// Email of the signed-in permanent account, if any.
    private(set) var email: String?

    var isAuthenticated: Bool { state == .authenticated }

    /// A permanent (non-anonymous) account is signed in on this device. Gate
    /// account-only flows on this — not on `isAuthenticated`, which is true for
    /// guests too.
    ///
    /// Who, not whether the server could be reached: a member whose session
    /// couldn't be confirmed (offline at launch, a stalled refresh — `.failed`
    /// keeps their stored session) is still that member. This used to require
    /// `.authenticated` too, so on a plane the journal asked a member to create
    /// an account and the You tab called them a guest. What they then reach
    /// for says "you're offline" itself. A session that is really gone is
    /// forgotten (`forgetMember`), which is what turns this off.
    var hasAccount: Bool { !isAnonymous }

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

    /// Why there's no session, while `needsRetry` is true. The banner words
    /// itself from this: "you're offline" and "we couldn't reach Soulfull"
    /// send someone after different problems.
    var connectionFailure: ConnectionFailure? {
        if case .failed(let failure) = state { return failure }
        return nil
    }

    /// True while `retry()` runs.
    ///
    /// Deliberately not a `state`. Retry used to set `.initializing`, which
    /// turned `needsRetry` off: the banner slid away the moment Retry was
    /// tapped and slid back on failure, so its spinner was never seen. `state`
    /// now stays `.failed` until the attempt settles.
    private(set) var isRetrying = false

    /// Re-attempt a session after a failed launch. Safe to call repeatedly.
    func retry() async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        await checkSession()
    }

    /// Restores an existing session or creates an anonymous one.
    /// Called once from `AppState.initializeAuth()` at launch.
    ///
    /// The session stored on this device says who this is without the
    /// network, so it is applied first. The launch screen stops waiting for
    /// the server after `AppState.launchGrace`, and without this a member who
    /// reached the app while their expired token was still refreshing on a
    /// stalled connection would look like a guest: the account gate would ask
    /// someone already signed in to sign in. The server check that follows confirms
    /// the session, replaces it with a guest only if it's really gone, or
    /// marks it `.failed` if it couldn't be reached.
    func initialize() async {
        if let stored = supabase.auth.currentUser { apply(stored) }
        await checkSession()
    }

    /// The session check that `initialize()` or `retry()` started, while it
    /// runs. A second caller joins it rather than starting another.
    private var sessionCheck: Task<Void, Never>?

    private func checkSession() async {
        if let sessionCheck { return await sessionCheck.value }
        let check = Task { await self.restoreSession() }
        sessionCheck = check
        await check.value
        if sessionCheck == check { sessionCheck = nil }
    }

    /// Lets a session check that's still running finish before something
    /// replaces the session.
    ///
    /// The app no longer waits on the logo for the launch check, so someone
    /// can reach the account sheet while it's still in flight on a stalled
    /// connection. Left to land afterwards, the check would undo what they
    /// just did: a late anonymous sign-in or token refresh overwrites the
    /// session they signed in with in the Keychain, and a late failure sets
    /// `.failed` over a healthy one.
    private func settleSessionCheck() async {
        await sessionCheck?.value
    }

    private func restoreSession() async {
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
            } else {
                Task { await self.syncMemberName() }
            }
        } catch {
            // Only a session that is really gone may be replaced by a guest.
            //
            // This used to send every error here to `signInAnonymously()`. An
            // expired access token makes the SDK refresh it, and a refresh that
            // fails on the *network* is thrown with the stored session left in
            // place, so a two-second glitch at launch signed a member out: the
            // new guest overwrote their session in the Keychain, and `apply`
            // saw a new identity and cleared their history and program
            // reminders. A session that merely couldn't be checked is kept,
            // and the banner's Retry restores it.
            switch SessionRestoreDecision(after: error) {
            case .openGuest:
                // First launch, a purged guest, a refresh token the server
                // refused: there is nothing to keep.
                forgetMember()
                await signInAnonymously()
            case .keepSession(let failure):
                Log.auth.error("Session restore failed, keeping the stored session: \(error.localizedDescription)")
                state = .failed(failure)
            }
        }
    }

    /// The address the account sheet should ask for a code for, or `nil` to
    /// open on the form. Read when the sheet appears, so closing it (or
    /// relaunching) no longer loses a sign-up halfway through.
    ///
    /// After a relaunch the only record is the stored guest's pending
    /// `newEmail`, which the email-change upgrade leaves on the user until
    /// it's confirmed. The no-session `signUp` fallback leaves nothing behind,
    /// so it resumes only within the launch it started in.
    var confirmationToResume: String? {
        let stored = supabase.auth.currentUser
        return PendingConfirmationRule.address(
            hasAccount: hasAccount,
            startedThisLaunch: pendingConfirmationEmail,
            setAside: confirmationSetAside,
            storedUser: stored.map {
                PendingConfirmationRule.StoredUser(isAnonymous: $0.isAnonymous,
                                                   newEmail: $0.newEmail,
                                                   sentAt: $0.emailChangeSentAt)
            },
            now: .now
        )
    }

    /// "Use a different sign-in": stop steering the sheet back to the code
    /// panel for this launch. The pending change stays on the server, and a
    /// new create replaces it.
    func setAsidePendingConfirmation() {
        pendingConfirmationEmail = nil
        confirmationSetAside = true
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
        await settleSessionCheck()
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
        pendingConfirmationEmail = email
        confirmationSetAside = false
        // With confirmation off (or already satisfied) the account is permanent
        // here, and `apply` clears what was just marked pending.
        apply(supabase.auth.currentUser)
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
        await settleSessionCheck()
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
                pendingConfirmationEmail = nil
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
        // A device with no answers has nothing to say, and the upsert writes
        // every field, so pushing would blank the row. That is exactly the
        // device of a member who signs in from Welcome before onboarding has
        // asked anything, and `mergeProfile` treats a row with a name but no
        // answers as new and pushes.
        let hasAnswers = !settings.userName.isEmpty || !settings.intentions.isEmpty
            || !settings.bodyState.isEmpty || !settings.frequency.isEmpty
        guard hasAnswers else { return }
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

    // MARK: - The member's name

    /// Brings this phone's copy of the member's name (`AppSettings.userName`:
    /// Home's greeting, the You tab, the nav bar's face) in line with their
    /// account, once the launch has confirmed the session. Best-effort.
    ///
    /// The copy used to be filled only at sign-in and on a You-tab visit, so
    /// after a reinstall, or a reset that left the session in the Keychain,
    /// Home greeted a signed-in member as "Friend".
    func syncMemberName() async {
        guard hasAccount, let id = userID else { return }
        do {
            guard let profile = try await SupabaseService.shared.fetchProfile(id: id) else { return }
            await reconcileName(with: profile)
        } catch where error.isCancellation {
            return
        } catch {
            Log.auth.info("Name check skipped: \(error.localizedDescription)")
        }
    }

    /// Applies `MemberNameDecision` to a profile row just read. A row that
    /// lost its name gets it back from the phone or the sign-up name, the way
    /// 0027 filled empty names on the server: onboarding once pushed the empty
    /// answer of a member it hadn't asked, which wiped the name. Best-effort.
    func reconcileName(with profile: Profile) async {
        guard hasAccount, userID == profile.id else { return }
        let signUp = supabase.auth.currentUser?.userMetadata["full_name"]?.stringValue ?? ""
        switch MemberNameDecision(profile: profile.fullName, device: settings.userName, signUp: signUp) {
        case .keep:
            return
        case .adopt(let name):
            settings.userName = name
        case .restore(let name):
            settings.userName = name
            do {
                try await SupabaseService.shared.setProfileName(name, userID: profile.id)
            } catch {
                Log.auth.error("Restoring the profile's name failed: \(error.localizedDescription)")
            }
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
        await settleSessionCheck()
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
        await settleSessionCheck()
        let session = try await supabase.auth.signIn(email: email, password: password)
        apply(session.user)
    }

    // MARK: - Forgot password

    /// Emails a code for choosing a new password.
    ///
    /// GoTrue answers the same whether or not an account uses the address,
    /// and sends nothing when none does, so the sheet moves on to the code
    /// either way and can't be used to find out who has an account.
    ///
    /// The email carries the code alone, no link: a recovery link opened on a
    /// laptop, or fetched by a mail scanner, would use up the code and lead
    /// nowhere (supabase/templates/README.md). The SDK still files a PKCE
    /// verifier for it, replacing any a pending confirmation link left. That
    /// link then can't finish on this phone, but opening it still confirms
    /// the address, which `refreshConfirmationState` picks up.
    func requestPasswordReset(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email)
    }

    /// Signs in with the code from a reset email. The code proves the address
    /// is theirs, so this is a sign-in like `signIn`: the member's session
    /// replaces the guest's. The new password is set separately, because a
    /// code is single-use and a refused password mustn't spend it.
    func verifyPasswordResetCode(_ code: String, email: String) async throws {
        await settleSessionCheck()
        let digits = String(code.filter(\.isNumber))
        let response = try await supabase.auth.verifyOTP(email: email, token: digits, type: .recovery)
        apply(response.session?.user ?? response.user)
    }

    /// Sets the signed-in member's password.
    func setNewPassword(_ password: String) async throws {
        let user = try await supabase.auth.update(user: UserAttributes(password: password))
        apply(user)
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
        // A cold launch from the emailed link opens the URL while the launch
        // check is still running.
        await settleSessionCheck()
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
        await settleSessionCheck()
        // While the session is still valid: this phone stops being theirs.
        await PushRegistrar.shared.forgetDevice()
        do {
            try await supabase.auth.signOut()
        } catch {
            Log.auth.error("Sign-out failed: \(error.localizedDescription)")
        }
        // The SDK drops the session from the device before it calls the
        // server, so it's gone whether or not that call worked.
        forgetMember()
        await SupabaseService.shared.invalidateCache()
        endConfirmationWatch()
        pendingConfirmation = nil
        pendingConfirmationEmail = nil
        confirmationSetAside = false
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

    /// The member's session is gone from this device: let go of who they were
    /// now, not when the guest that replaces them arrives. That used to wait
    /// for `signInAnonymously`, and when it failed (offline, or its rate
    /// limit) the member stayed: still not anonymous, their private data still
    /// in scope, their journal entry still open in a tab nobody rebuilt.
    private func forgetMember() {
        guard !isAnonymous else { return }
        apply(nil)
    }

    private func signInAnonymously() async {
        do {
            let session = try await supabase.auth.signInAnonymously()
            apply(session.user)
            state = .authenticated
        } catch {
            state = .failed(ConnectionFailure(error))
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
        if !isAnonymous {
            // A permanent account: whatever confirmation was pending is done,
            // or belonged to a guest this account replaced.
            pendingConfirmation = nil
            pendingConfirmationEmail = nil
        }

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

// MARK: - Launch-session rules

/// Why there's no session, in the terms the banner needs.
enum ConnectionFailure: Equatable, Sendable {
    /// This device has no connection (`Error.isOffline`).
    case offline
    /// The connection is there but Soulfull didn't answer usefully: a
    /// timeout, our backend erroring, a host that can't be reached.
    case unreachable

    init(_ error: any Error) {
        self = error.isOffline ? .offline : .unreachable
    }
}

/// What a failed session restore at launch means for the session stored on
/// this device. Decided from the error alone so the rule can be tested
/// without a network or a Keychain.
///
/// Leaning toward `keepSession` is the safe side. Keeping a dead session costs
/// one more tap on Retry; replacing a live one signs a member out and clears
/// their device state.
enum SessionRestoreDecision: Equatable, Sendable {
    /// There's no usable session: none was stored (a first launch), or the
    /// server refused its refresh token (signed out elsewhere, a purged guest,
    /// a deleted account). Open a fresh guest.
    case openGuest
    /// The session couldn't be checked. It may be perfectly good, so keep it
    /// and let Retry try again.
    case keepSession(ConnectionFailure)

    /// Statuses that mean GoTrue read the refresh token and said no. 408 and
    /// 429 are 4xx too, but they say "not now", not "never".
    private static let refusingStatuses: Set<Int> = [400, 401, 403]

    /// Codes that mean the session is gone for good. The SDK already turns
    /// the first four into `.sessionMissing` and deletes the session itself;
    /// they're repeated so a change in that mapping can't strand anyone on a
    /// session that will never refresh.
    private static let goneCodes: Set<ErrorCode> = [
        .sessionNotFound, .sessionExpired, .refreshTokenNotFound,
        .refreshTokenAlreadyUsed, .userNotFound,
    ]

    init(after error: any Error) {
        if let authError = error as? AuthError {
            switch authError {
            case .sessionMissing:
                self = .openGuest
                return
            case let .api(_, code, _, response):
                if Self.goneCodes.contains(code) {
                    self = .openGuest
                    return
                }
                // `.unexpectedFailure` is the SDK's label for a body it couldn't
                // read as a GoTrue error: a captive portal's login page, a
                // proxy's 403. That status is about the network, not the token.
                if code != .unexpectedFailure, Self.refusingStatuses.contains(response.statusCode) {
                    self = .openGuest
                    return
                }
            default:
                break
            }
        }
        self = .keepSession(ConnectionFailure(error))
    }
}

/// Which name this phone shows for a member, and whether their profile needs
/// it back. A member's name lives on their profile (0027); the phone's copy
/// only greets them. Members are named when they sign up (or by Apple's first
/// sign-in), so an empty profile is a lost name rather than a choice, and the
/// best name still known goes back onto it. Nothing is invented: with no name
/// anywhere (an Apple account that shared none) the phone keeps what it has.
enum MemberNameDecision: Equatable, Sendable {
    /// Nothing to change.
    case keep
    /// The phone takes the profile's name.
    case adopt(String)
    /// The profile has no name: the phone shows this one, and it is written
    /// back to the profile.
    case restore(String)

    init(profile: String, device: String, signUp: String) {
        let onProfile = profile.trimmingCharacters(in: .whitespaces)
        let onDevice = device.trimmingCharacters(in: .whitespaces)
        if !onProfile.isEmpty {
            self = onProfile == onDevice ? .keep : .adopt(onProfile)
            return
        }
        // The phone's copy is the more recent: it came from the profile or
        // from this member's own onboarding, after they signed up.
        let known = onDevice.isEmpty ? signUp.trimmingCharacters(in: .whitespaces) : onDevice
        self = known.isEmpty ? .keep : .restore(known)
    }
}

/// Whether an email confirmation is still waiting, and on which address, so
/// the account sheet can open on the code panel instead of a blank form.
enum PendingConfirmationRule {

    /// What the rule reads from the session stored on this device.
    struct StoredUser: Equatable, Sendable {
        var isAnonymous: Bool
        /// The address a guest's upgrade is waiting to confirm (`new_email`).
        var newEmail: String?
        /// When that confirmation email went out (`email_change_sent_at`).
        var sentAt: Date?
    }

    /// How long after the email a relaunched app still reopens the code panel
    /// by itself. The code may have expired sooner, but the panel can send a
    /// new one to the same address. After a day, someone who abandoned the
    /// sign-up shouldn't be steered back into it every time the sheet opens.
    static let resumeWindow: TimeInterval = 24 * 60 * 60

    static func address(hasAccount: Bool, startedThisLaunch: String?, setAside: Bool,
                        storedUser: StoredUser?, now: Date) -> String? {
        guard !hasAccount, !setAside else { return nil }
        if let started = startedThisLaunch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !started.isEmpty {
            return started
        }
        guard let user = storedUser, user.isAnonymous,
              let pending = user.newEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pending.isEmpty,
              // With no send time there's no telling how stale it is, and no
              // sign an email ever went out: the form is the safer opening.
              let sentAt = user.sentAt,
              now.timeIntervalSince(sentAt) < resumeWindow
        else { return nil }
        return pending
    }
}
