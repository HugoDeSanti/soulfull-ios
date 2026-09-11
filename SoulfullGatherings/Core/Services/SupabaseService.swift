import SwiftUI
@preconcurrency import Supabase

/// Singleton data layer. Implemented as an `actor` so its mutable cache is
/// safe to access from concurrent async contexts without explicit locking.
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

    private var retreatsCache: [Retreat]?
    private var retreatsCacheDate: Date?
    private var programsCache: [Program]?
    private var programsCacheDate: Date?
    private var practiceCache: [PracticeCategory: [PracticeSession]] = [:]
    private var practiceCacheDate: [PracticeCategory: Date] = [:]
    private var availableCategoriesCache: Set<PracticeCategory>?
    private var availableCategoriesCacheDate: Date?
    private let cacheTTL: TimeInterval = 300

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

    // MARK: - Fetches

    /// Retreats that have **not started yet**.
    ///
    /// Filtered server-side on `start_date > today`. It used to be
    /// `end_date >= today`, which kept a retreat listed for its whole duration
    /// — so on 2026-09-10 the catalog was still offering "Request a place" on
    /// Dolomites, which had begun two days earlier. A retreat you cannot join
    /// any more is not a catalog entry, it is a wrong price and a wrong date in
    /// front of a customer.
    ///
    /// Strictly greater than today: a retreat starting *this morning* has begun.
    func fetchRetreats() async throws -> [Retreat] {
        if let cache = retreatsCache,
           let date = retreatsCacheDate,
           Date().timeIntervalSince(date) < cacheTTL {
            return cache
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        // UTC, not the device's zone. `start_date` is a bare Postgres `date`,
        // so formatting "today" locally made the catalog disagree with itself
        // across time zones — a user in UTC+13 lost a retreat starting today,
        // one in UTC−11 kept seeing one that had already begun.
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        let today = fmt.string(from: Date())

        let rows: [RetreatRow] = try await client
            .from("retreats")
            .select()
            .gt("start_date", value: today)
            .order("start_date", ascending: true)
            .limit(50)
            .execute()
            .value
        let retreats = rows.map(\.retreat)
        retreatsCache = retreats
        retreatsCacheDate = Date()
        return retreats
    }

    func fetchPrograms() async throws -> [Program] {
        if let cache = programsCache,
           let date = programsCacheDate,
           Date().timeIntervalSince(date) < cacheTTL {
            return cache
        }
        let rows: [ProgramRow] = try await client
            .from("programs")
            .select()
            .order("title", ascending: true)
            .limit(50)
            .execute()
            .value
        let programs = rows.map(\.program)
        programsCache = programs
        programsCacheDate = Date()
        return programs
    }

    /// Which media tracks actually have sessions behind them.
    ///
    /// Which media tracks have sessions behind them — or `.unknown` if we
    /// couldn't find out.
    ///
    /// The distinction matters. This used to collapse "the table is empty" and
    /// "we're offline" into an empty set, and the Practice landing rendered
    /// both as three dimmed "Coming soon" cards: a user on a train was told the
    /// content doesn't exist. Offline, the honest answer is that we don't know
    /// — the same answer `ConnectionBanner` is already giving them — so let the
    /// caller keep the tracks open and surface the real error on the list.
    enum CategoryAvailability {
        case known(Set<PracticeCategory>)
        /// Offline, or the check itself failed. Not "nothing here".
        case unknown
    }

    func availablePracticeCategories() async -> CategoryAvailability {
        if let cached = availableCategoriesCache,
           let date = availableCategoriesCacheDate,
           Date().timeIntervalSince(date) < cacheTTL {
            return .known(cached)
        }
        struct CategoryRow: Decodable { let category: String }
        do {
            let rows: [CategoryRow] = try await client
                .from("practice_sessions")
                .select("category")
                .limit(500)
                .execute()
                .value
            let set = Set(rows.compactMap { PracticeCategory(rawValue: $0.category) })
            availableCategoriesCache = set
            availableCategoriesCacheDate = Date()
            return .known(set)
        } catch {
            // Not cached, so it re-checks on the next visit.
            Log.data.info("Practice availability unknown: \(error.localizedDescription)")
            return .unknown
        }
    }

    /// Sessions for one practice track, newest-friendly ordering by title.
    func fetchPracticeSessions(category: PracticeCategory) async throws -> [PracticeSession] {
        if let cache = practiceCache[category],
           let date = practiceCacheDate[category],
           Date().timeIntervalSince(date) < cacheTTL {
            return cache
        }
        let rows: [PracticeSessionRow] = try await client
            .from("practice_sessions")
            .select()
            .eq("category", value: category.rawValue)
            .order("title", ascending: true)
            .limit(100)
            .execute()
            .value
        let sessions = rows.map(\.session)
        practiceCache[category] = sessions
        practiceCacheDate[category] = Date()
        return sessions
    }

    // MARK: - Profiles

    /// Fetches the profile row for a user id, or `nil` if none exists yet.
    /// Not cached — profiles are small and change with user edits / sign-in.
    func fetchProfile(id: UUID) async throws -> Profile? {
        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.profile
    }

    /// Inserts or updates the caller's profile. RLS enforces that `profile.id`
    /// matches the signed-in user. `stripeCustomerId` is deliberately not sent —
    /// it is owned by the Phase 2 webhook.
    func upsertProfile(_ profile: Profile) async throws {
        let payload = ProfileUpsert(
            id: profile.id,
            fullName: profile.fullName,
            intentions: profile.intentions,
            bodyState: profile.bodyState,
            frequency: profile.frequency
        )
        try await client
            .from("profiles")
            .upsert(payload)
            .execute()
    }

    // MARK: - Bookings

    /// The most recent booking the signed-in user has for a retreat, if any.
    /// RLS guarantees only the caller's own rows are visible; the explicit
    /// `user_id` filter just makes intent obvious. Uncached — reservation state
    /// must always reflect the latest webhook write.
    func fetchBooking(retreatID: Int, userID: UUID) async throws -> Booking? {
        let rows: [BookingRow] = try await client
            .from("bookings")
            .select()
            .eq("user_id", value: userID)
            .eq("retreat_id", value: retreatID)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first?.booking
    }

    // MARK: - Practice progress

    /// Records (or tops up) one playback/reading session in `practice_plays`.
    ///
    /// Upserted on `(user_id, client_event_id)` so the periodic heartbeat during
    /// a listen keeps updating the same row rather than minting a new one —
    /// which is what stops a creator being paid several times over for a single
    /// play. The DB trigger clamps `seconds_played` to the practice's length and
    /// refuses to let it go backwards, so a replayed heartbeat is harmless.
    ///
    /// Uncached, and deliberately fire-and-forget at the call site: losing a
    /// heartbeat costs a few seconds of attribution, and blocking playback on a
    /// network write would cost far more.
    func recordPracticePlay(_ play: PracticePlay,
                            userID: UUID,
                            secondsPlayed: Int,
                            positionSeconds: Int,
                            completed: Bool) async throws {
        let payload = PracticePlayUpsert(
            userId: userID,
            clientEventId: play.eventID,
            contentKind: play.kind.rawValue,
            contentId: play.contentID,
            contentTitle: play.title,
            creator: play.creator,
            category: play.category?.rawValue,
            secondsPlayed: max(0, secondsPlayed),
            positionSeconds: max(0, positionSeconds),
            durationSeconds: play.durationSeconds,
            completed: completed
        )
        try await client
            .from("practice_plays")
            .upsert(payload, onConflict: "user_id,client_event_id")
            .execute()
    }

    /// Everything this member has played, newest first. Reads the
    /// `practice_progress` view, which aggregates the ledger — so the resume
    /// point the app shows and the seconds a creator is paid for come from the
    /// same rows and can't drift apart.
    ///
    /// RLS on the underlying table (through the view's `security_invoker`) means
    /// only the caller's own rows come back; the `user_id` filter is belt and
    /// braces. Uncached — it changes every time they press play.
    func fetchPracticeProgress(userID: UUID, limit: Int = 200) async throws -> [PracticeProgress] {
        let rows: [PracticeProgressRow] = try await client
            .from("practice_progress")
            .select()
            .eq("user_id", value: userID)
            .order("last_played_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.map(\.progress)
    }

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

    func invalidateCache() {
        retreatsCache = nil
        retreatsCacheDate = nil
        programsCache = nil
        programsCacheDate = nil
        practiceCache.removeAll()
        practiceCacheDate.removeAll()
        availableCategoriesCache = nil
        availableCategoriesCacheDate = nil
    }
}

// MARK: - DTOs

/// Read model for `profiles`. Tolerant of nulls so a freshly-created (trigger)
/// row with only an id still decodes.
private struct ProfileRow: Decodable {
    let id: UUID
    let email: String?
    let fullName: String?
    let intentions: [String]?
    let bodyState: String?
    let frequency: String?
    let stripeCustomerId: String?

    enum CodingKeys: String, CodingKey {
        case id, email, intentions, frequency
        case fullName         = "full_name"
        case bodyState        = "body_state"
        case stripeCustomerId = "stripe_customer_id"
    }

    var profile: Profile {
        Profile(
            id: id,
            email: email ?? "",
            fullName: fullName ?? "",
            intentions: intentions ?? [],
            bodyState: bodyState ?? "",
            frequency: frequency ?? "",
            stripeCustomerId: stripeCustomerId
        )
    }
}

/// Write model for `profiles` — only the columns the app owns. Excludes
/// `stripe_customer_id` and timestamps (DB defaults / trigger), and **`email`**.
///
/// `email` used to be sent from here. RLS only ever asserted `auth.uid() = id`,
/// so the column was client-writable, and `create-payment-intent` preferred it
/// over the verified `user.email` when creating the Stripe customer — letting a
/// member point their Stripe record, and its receipts, at an address they
/// don't own. The column is now server-owned: 0009 reverts client writes to it
/// and mirrors `auth.users.email` into it on every change.
private struct ProfileUpsert: Encodable {
    let id: UUID
    let fullName: String
    let intentions: [String]
    let bodyState: String
    let frequency: String

    enum CodingKeys: String, CodingKey {
        case id, intentions, frequency
        case fullName  = "full_name"
        case bodyState = "body_state"
    }
}

/// Read model for `bookings`. `created_at` decodes straight to `Date` via the
/// client's default (Postgres-timestamp-aware) decoder.
private struct BookingRow: Decodable {
    let id: UUID
    let retreatId: Int
    let amountCents: Int
    let currency: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, currency, status
        case retreatId   = "retreat_id"
        case amountCents = "amount_cents"
        case createdAt   = "created_at"
    }

    var booking: Booking {
        Booking(id: id, retreatId: retreatId, amountCents: amountCents,
                currency: currency, status: status, createdAt: createdAt)
    }
}

private struct RetreatRow: Codable {
    let id: Int
    let name: String
    let country: String
    let startDate: String
    let endDate: String
    let maxGuests: Int
    let priceUsd: Int
    let tags: [String]?
    let blurb: String
    let imageUrl: String
    let toneTop: String
    let toneMid: String
    let toneBase: String
    let groupChatUrl: String?
    /// The long-form brochure, as a jsonb document. Decoded separately (see
    /// `experience`) so one malformed blob can't take the whole catalog down.
    let experience: AnyJSON?

    enum CodingKeys: String, CodingKey {
        case id, name, country, tags, blurb, experience
        case imageUrl      = "image_url"
        case startDate     = "start_date"
        case endDate       = "end_date"
        case maxGuests     = "max_guests"
        case priceUsd      = "price_usd"
        case toneTop       = "tone_top"
        case toneMid       = "tone_mid"
        case toneBase      = "tone_base"
        case groupChatUrl  = "group_chat_url"
    }

    /// Decoder for the `experience` document.
    ///
    /// Keys inside the jsonb are snake_case like every column, so this converts
    /// rather than making every nested type carry `CodingKeys` — there are
    /// thirteen multi-word keys across eight types, and hand-maintaining them
    /// is thirteen chances to typo a key that then silently drops a section.
    private static let experienceDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// The decoded brochure, or `nil` if there isn't one **or it's malformed**.
    ///
    /// Failing soft is the point. This is content someone hand-authors in the
    /// dashboard; a missing comma must not blank the catalog. A retreat with an
    /// undecodable document simply falls back to the concise detail layout,
    /// exactly as one with no document does — and the reason lands in the log.
    var decodedExperience: RetreatExperience? {
        guard let experience, experience != .null else { return nil }
        do {
            let data = try JSONEncoder().encode(experience)
            return try Self.experienceDecoder.decode(RetreatExperience.self, from: data)
        } catch {
            Log.data.error("Retreat \(self.id, privacy: .public) has an unreadable experience document: \(error.localizedDescription)")
            return nil
        }
    }

    var retreat: Retreat {
        // Local formatter — only called during data loads, not in tight loops.
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let start = fmt.date(from: startDate) ?? Date()
        let end   = fmt.date(from: endDate)   ?? Date()
        return Retreat(
            id: id, name: name, country: country,
            startDate: start, endDate: end,
            maxGuests: maxGuests, priceUsd: priceUsd,
            tags: tags ?? [], blurb: blurb, imageUrl: imageUrl,
            toneTop:  Color(hex: toneTop),
            toneMid:  Color(hex: toneMid),
            toneBase: Color(hex: toneBase),
            // Scheme-checked at the decode boundary, so nothing downstream has
            // to remember. The hub hands this straight to `openURL`, and
            // `URL(string:)` accepts any scheme — a mis-seeded or tampered row
            // could have opened an arbitrary app. WhatsApp invites are https.
            groupChatURL: groupChatUrl
                .flatMap { URL(string: $0) }
                .flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil },
            experience: decodedExperience
        )
    }
}

private struct ProgramRow: Codable {
    let id: String
    let title: String
    let lead: String
    let dateRange: String
    let days: Int
    let imageUrl: String

    enum CodingKeys: String, CodingKey {
        case id, title, lead, days
        case dateRange = "date_range"
        case imageUrl  = "image_url"
    }

    var program: Program {
        Program(id: id, title: title, lead: lead, when: dateRange, days: days, imageUrl: imageUrl)
    }
}

private struct PracticeSessionRow: Codable {
    let id: Int
    let category: String
    let title: String
    let lead: String
    let mediaKind: String
    let storagePath: String
    let durationSeconds: Int
    let imageUrl: String
    let blurb: String?

    enum CodingKeys: String, CodingKey {
        case id, category, title, lead, blurb
        case mediaKind       = "media_kind"
        case storagePath     = "storage_path"
        case durationSeconds = "duration_seconds"
        case imageUrl        = "image_url"
    }

    var session: PracticeSession {
        PracticeSession(
            id: id,
            category: PracticeCategory(rawValue: category) ?? .somatic,
            title: title,
            lead: lead,
            mediaKind: MediaKind(rawValue: mediaKind) ?? .audio,
            storagePath: storagePath,
            durationSeconds: durationSeconds,
            imageUrl: imageUrl,
            blurb: blurb ?? ""
        )
    }
}


/// Write model for `practice_plays`. `id`, `started_at`, `created_at` and
/// `updated_at` are all DB-managed (defaults + the integrity trigger), so they
/// are deliberately absent.
private struct PracticePlayUpsert: Encodable {
    let userId: UUID
    let clientEventId: UUID
    let contentKind: String
    let contentId: Int
    let contentTitle: String
    let creator: String?
    let category: String?
    let secondsPlayed: Int
    let positionSeconds: Int
    let durationSeconds: Int?
    let completed: Bool

    enum CodingKeys: String, CodingKey {
        case creator, category, completed
        case userId          = "user_id"
        case clientEventId   = "client_event_id"
        case contentKind     = "content_kind"
        case contentId       = "content_id"
        case contentTitle    = "content_title"
        case secondsPlayed   = "seconds_played"
        case positionSeconds = "position_seconds"
        case durationSeconds = "duration_seconds"
    }
}

/// Read model for the `practice_progress` view.
private struct PracticeProgressRow: Decodable {
    let contentKind: String
    let contentId: Int
    let contentTitle: String
    let creator: String?
    let category: String?
    let positionSeconds: Int
    let durationSeconds: Int?
    let totalSecondsPlayed: Int
    let completed: Bool
    let playCount: Int
    let lastPlayedAt: Date

    enum CodingKeys: String, CodingKey {
        case creator, category, completed
        case contentKind        = "content_kind"
        case contentId          = "content_id"
        case contentTitle       = "content_title"
        case positionSeconds    = "position_seconds"
        case durationSeconds    = "duration_seconds"
        case totalSecondsPlayed = "total_seconds_played"
        case playCount          = "play_count"
        case lastPlayedAt       = "last_played_at"
    }

    var progress: PracticeProgress {
        PracticeProgress(
            kind: PracticeContentKind(rawValue: contentKind) ?? .session,
            contentID: contentId,
            title: contentTitle,
            creator: creator,
            category: category.flatMap(PracticeCategory.init(rawValue:)),
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            totalSecondsPlayed: totalSecondsPlayed,
            completed: completed,
            playCount: playCount,
            lastPlayedAt: lastPlayedAt
        )
    }
}
