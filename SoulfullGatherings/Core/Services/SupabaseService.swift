//
//  SupabaseService.swift
//  Soulfull Gatherings
//
//  The data layer: one actor around the Supabase client. Its calls live in
//  extensions by area, each file beside the DTOs it decodes:
//    +Catalog    retreats, digital retreats, practice tracks, the written
//                libraries, guides (cached: `CatalogCache`)
//    +Member     a member's own rows: enrolments, profile, bookings, the
//                practice ledger, photo
//    +Community  the feed, friends, safety, likes, presence, push
//    +Guide      the guide dashboard
//

import SwiftUI
@preconcurrency import Supabase

/// Singleton data layer, an `actor`. The catalog's cache is an actor of its
/// own (`CatalogCache`); member data is never cached.
actor SupabaseService {

    /// Bootstrap failure is fatal in DEBUG (a missing `Secrets.xcconfig` should
    /// stop a developer immediately) but **not** in Release: a bad build
    /// configuration would ship as a launch crash, which App Review rejects
    /// under Guideline 2.1 and which tells the user nothing. In Release the
    /// client is built against a placeholder host, every request fails, and
    /// `AuthManager` surfaces it through the existing `ConnectionBanner` retry
    /// path — visible and diagnosable instead of a dead icon.
    static let shared: SupabaseService = {
        do {
            return try SupabaseService()
        } catch {
            #if DEBUG
            fatalError("""
                [SupabaseService] \(error)
                Copy Config/Secrets.xcconfig.example → Config/Secrets.xcconfig and fill in your values.
                """)
            #else
            Log.data.error("Supabase bootstrap failed: \(error.localizedDescription)")
            return SupabaseService(unconfigured: true)
            #endif
        }
    }()

    /// Exposed `nonisolated` so callers (e.g. `AuthManager`) can grab it
    /// synchronously without hopping through the actor's executor.
    nonisolated let client: SupabaseClient

    /// The catalog's reads, kept five minutes and shared while in flight.
    /// Nothing invalidates it but `invalidateCache()`.
    let catalog = CatalogCache()

    /// Deep-link the app handles for auth email confirmations / magic links.
    /// Must be allow-listed in Supabase → Authentication → URL Configuration,
    /// and registered as a URL scheme in `project.yml` (`soulfull`).
    nonisolated static let authRedirectURL = URL(string: "soulfull://auth-callback")!

    private init() throws {
        let config = try SupabaseConfig.make()
        // PKCE flow + Keychain session storage are the SDK defaults; we add the
        // redirect URL so signUp / anonymous-upgrade confirmation emails return
        // to the app instead of a web page.
        let options = SupabaseClientOptions(
            auth: .init(redirectToURL: Self.authRedirectURL)
        )
        client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey, options: options)
    }

    /// Release-only fallback for a build whose credentials didn't resolve.
    /// Every call fails and surfaces through the connection banner — see the
    /// note on `shared`. Never reached in DEBUG, which still traps.
    private init(unconfigured: Bool) {
        client = SupabaseClient(
            supabaseURL: URL(string: "https://unconfigured.invalid")!,
            supabaseKey: "unconfigured",
            options: SupabaseClientOptions(auth: .init(redirectToURL: Self.authRedirectURL))
        )
    }

    // MARK: - Storage

    /// Resolves a private Storage object path into a time-limited playable URL.
    /// Media in a *public* bucket can skip this and use its permanent URL.
    func signedMediaURL(path: String,
                        bucket: String = "practice-media",
                        expiresIn: Int = 3600) async throws -> URL {
        try await client.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: expiresIn)
    }

    /// Public URL for an object in a **public** bucket — no signing, no round
    /// trip, just a string. Catalog photography is marketing material shown to
    /// anonymous guests, so it has no business behind a signed URL: a public
    /// object is cacheable by `URLSession`, survives offline, and never expires
    /// mid-scroll the way a 1-hour signature does.
    ///
    /// `nonisolated` so `ImageSource` can resolve one synchronously while
    /// building a view, without hopping onto the actor.
    ///
    /// Private media (`practice-media`) still goes through `signedMediaURL`.
    nonisolated func publicObjectURL(bucket: String, path: String) -> URL? {
        try? client.storage.from(bucket).getPublicURL(path: path)
    }

    // MARK: - Cache

    /// Forgets the catalog (sign-out, a deliberate refresh). Member data is
    /// never cached.
    func invalidateCache() async {
        await catalog.clear()
    }
}

extension Error {
    /// The server refused a friend request because the last one to the same
    /// person was declined less than 30 days ago (0028's
    /// `enforce_friend_request_cooldown`, which raises exactly this message).
    var isFriendRequestCooldown: Bool {
        (self as? PostgrestError)?.message == "friend_request_cooldown"
    }

    /// The server turned a comment down for what it says — a link, the
    /// language, the hourly allowance (0032) — rather than failing to take it.
    var commentRefusal: CommentRefusal? {
        (self as? CommentRefusal) ?? CommentRefusal(message: (self as? PostgrestError)?.message)
    }

    /// The database itself refused the request, with a SQLSTATE (23503 not a
    /// practice, 42501 row-level security, …): asked again, it says the same.
    /// Not offline, a timeout or the gateway, and not PostgREST's own `PGRST…`
    /// codes, which include failing to reach the database and an expired
    /// token — those can pass next time.
    var isDatabaseRefusal: Bool {
        guard let code = (self as? PostgrestError)?.code else { return false }
        return !code.hasPrefix("PGRST")
    }
}
