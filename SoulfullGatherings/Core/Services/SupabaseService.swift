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
    private var instructorsCache: [Instructor]?
    private var instructorsCacheDate: Date?
    private var creditsCache: [PracticeCredit]?
    private var creditsCacheDate: Date?
    private var writtenCache: WrittenLibrary?
    private var writtenCacheDate: Date?
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

    /// Specific retreats, **whatever their dates** — the ones a member's
    /// bookings point at. `fetchRetreats()` keeps only what hasn't started, so
    /// it can never answer "which retreats have I been on"; this can.
    ///
    /// Uncached: it's keyed by the member's own history rather than shared,
    /// and a cache keyed the catalog's way would never hit.
    func fetchRetreats(ids: [Int]) async throws -> [Retreat] {
        guard !ids.isEmpty else { return [] }
        let rows: [RetreatRow] = try await client
            .from("retreats")
            .select()
            .in("id", values: ids)
            .order("start_date", ascending: false)
            .limit(50)
            .execute()
            .value
        return rows.map(\.retreat)
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
            // Draft programs stay invisible, so a curriculum can be authored in
            // the dashboard over several sittings without appearing half-built.
            .eq("published", value: true)
            .order("sort_order", ascending: true, nullsFirst: false)
            .order("title", ascending: true)
            .limit(50)
            .execute()
            .value
        let programs = rows.map(\.program)
        programsCache = programs
        programsCacheDate = Date()
        return programs
    }

    /// Specific programs, **published or not** — the ones a member has joined.
    /// A program taken down after someone finished it is still part of their
    /// history; the row's `published` flag says whether it can still be opened.
    /// The select policy is `using (true)`, so drafts are readable; the catalog
    /// hides them client-side, and so does everything but the You tab.
    func fetchPrograms(ids: [String]) async throws -> [Program] {
        guard !ids.isEmpty else { return [] }
        let rows: [ProgramRow] = try await client
            .from("programs")
            .select()
            .in("id", values: ids)
            .limit(50)
            .execute()
            .value
        return rows.map(\.program)
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
                // Program-only media must not light up a Practice track the
                // user can then open and find empty.
                .eq("program_only", value: false)
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
            // See `program_only` in 0013: media that belongs to a program
            // curriculum only, and is reachable from there.
            .eq("program_only", value: false)
            .order("title", ascending: true)
            .limit(100)
            .execute()
            .value
        let sessions = rows.map(\.session)
        practiceCache[category] = sessions
        practiceCacheDate[category] = Date()
        return sessions
    }

    /// Specific sessions by id, for a program curriculum.
    ///
    /// Deliberately **not** filtered on `program_only`: a curriculum is allowed
    /// to reference both shared library sessions and its own exclusive ones —
    /// that flag hides media from the Practice tab, it does not hide it from
    /// the program that owns it.
    ///
    /// Uncached. A curriculum resolves once per screen and the per-category
    /// caches are keyed the wrong way to help here.
    func fetchPracticeSessions(ids: [Int]) async throws -> [PracticeSession] {
        guard !ids.isEmpty else { return [] }
        let rows: [PracticeSessionRow] = try await client
            .from("practice_sessions")
            .select()
            .in("id", values: ids)
            .limit(200)
            .execute()
            .value
        return rows.map(\.session)
    }

    // MARK: - Written practices

    /// Journal prompts, movement sequences and recipes (0021) — published rows
    /// only, which RLS enforces, in the team's order. Read together because
    /// every caller wants all three, and cached like the rest of the catalog.
    ///
    /// All or nothing: one failed table fails the read, so a library is never
    /// quietly empty just because its request was the one that dropped.
    func fetchWrittenLibrary() async throws -> WrittenLibrary {
        if let cache = writtenCache,
           let date = writtenCacheDate,
           Date().timeIntervalSince(date) < cacheTTL {
            return cache
        }
        async let journals: [JournalPromptRow] = client
            .from("journal_prompts")
            .select(JournalPromptRow.columns)
            .order("sort_order", ascending: true, nullsFirst: false)
            .order("id", ascending: true)
            .limit(200)
            .execute()
            .value
        async let exercises: [ExerciseRow] = client
            .from("exercises")
            .select(ExerciseRow.columns)
            .order("sort_order", ascending: true, nullsFirst: false)
            .order("id", ascending: true)
            .limit(200)
            .execute()
            .value
        async let recipes: [RecipeRow] = client
            .from("recipes")
            .select(RecipeRow.columns)
            .order("sort_order", ascending: true, nullsFirst: false)
            .order("id", ascending: true)
            .limit(200)
            .execute()
            .value
        let library = try await WrittenLibrary(journals: journals.map(\.journalPrompt),
                                               exercises: exercises.map(\.exercise),
                                               recipes: recipes.map(\.recipe))
        writtenCache = library
        writtenCacheDate = Date()
        return library
    }

    // MARK: - Programs (enrolment + day completion)

    /// Every program this member has joined. Uncached — it changes the moment
    /// they enrol, and a stale enrolment shows the wrong CTA.
    func fetchProgramEnrollments(userID: UUID) async throws -> [ProgramEnrollment] {
        let rows: [ProgramEnrollmentRow] = try await client
            .from("program_enrollments")
            .select()
            .eq("user_id", value: userID)
            .order("enrolled_at", ascending: false)
            .limit(50)
            .execute()
            .value
        return rows.map(\.enrollment)
    }

    /// Every day this member has finished, across every program.
    func fetchProgramDayCompletions(userID: UUID) async throws -> [ProgramDayCompletion] {
        let rows: [ProgramDayCompletionRow] = try await client
            .from("program_day_completions")
            .select()
            .eq("user_id", value: userID)
            .order("day_number", ascending: true)
            .limit(500)
            .execute()
            .value
        return rows.map(\.completion)
    }

    /// Joins a program, returning the row the server wrote.
    ///
    /// `enrolled_at` matters beyond bookkeeping: it is **day 1's unlock
    /// moment**, and every activity is judged complete or not by whether it was
    /// finished after it. So the server's clock sets it, not the device's —
    /// the same clock that stamps `practice_plays.started_at`, which is what it
    /// gets compared against.
    func enrollInProgram(id programID: String, userID: UUID) async throws -> ProgramEnrollment {
        struct Insert: Encodable {
            let userId: UUID
            let programId: String
            enum CodingKeys: String, CodingKey {
                case userId = "user_id", programId = "program_id"
            }
        }
        let rows: [ProgramEnrollmentRow] = try await client
            .from("program_enrollments")
            // Re-joining a program keeps the original enrolment — leaving is an
            // explicit act, and an accidental double tap must not silently
            // restart someone's week.
            .upsert(Insert(userId: userID, programId: programID),
                    onConflict: "user_id,program_id",
                    ignoreDuplicates: true)
            .execute()
            .value
        if let existing = rows.first?.enrollment { return existing }
        // `ignoreDuplicates` returns nothing when the row was already there.
        let current: [ProgramEnrollmentRow] = try await client
            .from("program_enrollments")
            .select()
            .eq("user_id", value: userID)
            .eq("program_id", value: programID)
            .limit(1)
            .execute()
            .value
        guard let enrollment = current.first?.enrollment else {
            throw AppError.unknown
        }
        return enrollment
    }

    /// Leaves a program: the enrolment and every day completion for it.
    ///
    /// Note what is **not** deleted — `practice_plays`. The practices were
    /// genuinely done and their creators genuinely earned from them; leaving a
    /// program is the member withdrawing from a schedule, not rewriting
    /// history. Re-joining later starts the days again from an empty slate,
    /// which is the point.
    func leaveProgram(id programID: String, userID: UUID) async throws {
        try await client
            .from("program_day_completions")
            .delete()
            .eq("user_id", value: userID)
            .eq("program_id", value: programID)
            .execute()
        try await client
            .from("program_enrollments")
            .delete()
            .eq("user_id", value: userID)
            .eq("program_id", value: programID)
            .execute()
    }

    /// Marks one day finished and returns the moment the server recorded.
    ///
    /// That timestamp is the input to the next day's unlock, so it comes back
    /// from the database rather than being assumed — and it is **latched**: an
    /// existing row is left exactly as it was. Re-completing a day (replaying
    /// its activities, say) must not push tomorrow further away.
    @discardableResult
    func completeProgramDay(programID: String, day: Int, userID: UUID) async throws -> Date {
        struct Insert: Encodable {
            let userId: UUID
            let programId: String
            let dayNumber: Int
            enum CodingKeys: String, CodingKey {
                case userId = "user_id", programId = "program_id", dayNumber = "day_number"
            }
        }
        do {
            let rows: [ProgramDayCompletionRow] = try await client
                .from("program_day_completions")
                .upsert(Insert(userId: userID, programId: programID, dayNumber: day),
                        onConflict: "user_id,program_id,day_number",
                        ignoreDuplicates: true)
                .execute()
                .value
            if let completed = rows.first?.completedAt { return completed }
        } catch {
            // Already recorded is the common case here, and it is not a
            // failure — fall through and read back what is stored.
            Log.data.info("Program day insert fell through: \(error.localizedDescription)")
        }
        let current: [ProgramDayCompletionRow] = try await client
            .from("program_day_completions")
            .select()
            .eq("user_id", value: userID)
            .eq("program_id", value: programID)
            .eq("day_number", value: day)
            .limit(1)
            .execute()
            .value
        guard let completed = current.first?.completedAt else {
            throw AppError.unknown
        }
        return completed
    }

    /// Stamps the enrolment as finished, once the last day is done.
    func markProgramCompleted(id programID: String, userID: UUID, at date: Date = .now) async throws {
        struct Update: Encodable {
            let completedAt: Date
            enum CodingKeys: String, CodingKey { case completedAt = "completed_at" }
        }
        try await client
            .from("program_enrollments")
            .update(Update(completedAt: date))
            .eq("user_id", value: userID)
            .eq("program_id", value: programID)
            .is("completed_at", value: nil)
            .execute()
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
    /// Sends one retreat application to the team, via the
    /// `send-retreat-enquiry` Edge Function.
    ///
    /// Uncached and never retried here — a silent retry on an opaque failure
    /// is how a team ends up with the same application three times. The form
    /// keeps the answers and offers the retry to the person instead.
    ///
    /// The applicant's email address is deliberately absent from `enquiry`:
    /// the function reads it from the caller's JWT, so the address on the
    /// application is always the one on the account.
    func sendRetreatEnquiry(_ enquiry: RetreatEnquiry) async throws {
        struct SendResult: Decodable { let sent: Bool }
        let result: SendResult = try await client.functions.invoke(
            "send-retreat-enquiry",
            options: FunctionInvokeOptions(body: enquiry)
        )
        guard result.sent else { throw AppError.unknown }
    }

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

    /// Every retreat this member has **paid** for, newest first. A pending,
    /// failed or refunded booking is not a retreat they were on. RLS (select
    /// for the owner only) is the real filter; the `user_id` match is belt and
    /// braces, as everywhere else. Uncached.
    func fetchPaidBookings(userID: UUID) async throws -> [Booking] {
        let rows: [BookingRow] = try await client
            .from("bookings")
            .select()
            .eq("user_id", value: userID)
            .eq("status", value: "paid")
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
        return rows.map(\.booking)
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

    /// Every sitting this member has recorded — the raw ledger rows rather than
    /// the per-practice aggregate — reduced to the four columns the You tab's
    /// numbers need.
    ///
    /// The aggregate can't answer these questions. `practice_progress` keeps
    /// one `last_played_at` per practice, so a meditation done every morning
    /// for a week looks like one day of practice, and a best streak can't be
    /// recovered from it at all. The days are bucketed on the device, not in
    /// SQL, because "which day" depends on the member's time zone.
    ///
    /// Paged, since PostgREST caps a response at 1,000 rows and a daily
    /// practitioner passes that in a year. Bounded, so a runaway can't page
    /// forever. RLS returns only the caller's rows. Uncached.
    func fetchPracticeLedger(userID: UUID) async throws -> [PracticePlayRecord] {
        let pageSize = 1000
        let maxPages = 20
        var records: [PracticePlayRecord] = []
        for page in 0..<maxPages {
            let from = page * pageSize
            let rows: [PracticePlayRecordRow] = try await client
                .from("practice_plays")
                .select("client_event_id, content_kind, seconds_played, completed, started_at")
                .eq("user_id", value: userID)
                // A total order, so a row can't straddle two pages and be
                // counted twice or not at all.
                .order("started_at", ascending: true)
                .order("client_event_id", ascending: true)
                .range(from: from, to: from + pageSize - 1)
                .execute()
                .value
            records.append(contentsOf: rows.compactMap(\.record))
            if rows.count < pageSize { break }
        }
        return records
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

    // MARK: - Instructors

    /// Every published guide, in the team's order. Cached like the rest of the
    /// catalog.
    ///
    /// The columns are named rather than `*`: `user_id` is withheld from client
    /// roles by column grant (0019), and PostgREST answers a `*` over a column
    /// you may not read with 42501 rather than leaving it out.
    func fetchInstructors() async throws -> [Instructor] {
        if let cache = instructorsCache,
           let date = instructorsCacheDate,
           Date().timeIntervalSince(date) < cacheTTL {
            return cache
        }
        let rows: [InstructorRow] = try await client
            .from("instructors")
            .select(InstructorRow.columns)
            .eq("published", value: true)
            .order("sort_order", ascending: true, nullsFirst: false)
            .order("name", ascending: true)
            .limit(100)
            .execute()
            .value
        let instructors = rows.map(\.instructor)
        instructorsCache = instructors
        instructorsCacheDate = Date()
        return instructors
    }

    /// Which guide each written practice is credited to (0020). Catalog data,
    /// cached like the rest of it; a few dozen rows at most.
    func fetchPracticeCredits() async throws -> [PracticeCredit] {
        if let cache = creditsCache,
           let date = creditsCacheDate,
           Date().timeIntervalSince(date) < cacheTTL {
            return cache
        }
        let rows: [PracticeCreditRow] = try await client
            .from("practice_credits")
            .select()
            .limit(500)
            .execute()
            .value
        let credits = rows.compactMap(\.credit)
        creditsCache = credits
        creditsCacheDate = Date()
        return credits
    }

    /// The numbers on a guide's page, through `instructor_social()`. Nil for a
    /// guide who isn't published (or doesn't exist). Uncached: it moves every
    /// time someone follows, and the caller's own follow is part of it.
    func fetchInstructorSocial(id: String) async throws -> InstructorSocial? {
        let rows: [InstructorSocialRow] = try await client
            .rpc("instructor_social", params: ["p_instructor_id": id])
            .execute()
            .value
        return rows.first?.social
    }

    /// What a guide has published: their published digital retreats, their
    /// Practice-tab sessions, and the written practices credited to them.
    /// `program_only` media is left out — it belongs to its program and is
    /// reached from there, the same line the Practice tab draws. Uncached,
    /// except for the credits, which are catalog.
    func fetchInstructorLibrary(id: String) async throws -> InstructorLibrary {
        let sessionRows: [PracticeSessionRow] = try await client
            .from("practice_sessions")
            .select()
            .eq("instructor_id", value: id)
            .eq("program_only", value: false)
            .order("title", ascending: true)
            .limit(200)
            .execute()
            .value
        let programRows: [ProgramRow] = try await client
            .from("programs")
            .select()
            .eq("instructor_id", value: id)
            .eq("published", value: true)
            .order("sort_order", ascending: true, nullsFirst: false)
            .order("title", ascending: true)
            .limit(50)
            .execute()
            .value
        let credits = try await fetchPracticeCredits().filter { $0.instructorID == id }
        // Throws with the rest when it's needed: a guide known only for written
        // practices would otherwise read as having published nothing.
        let library = credits.isEmpty ? WrittenLibrary.empty : try await fetchWrittenLibrary()
        return InstructorLibrary(programs: programRows.map(\.program),
                                 sessions: sessionRows.map(\.session),
                                 credits: credits,
                                 library: library)
    }

    /// Follows a guide. Idempotent: a second follow is a duplicate key, and
    /// the thing asked for is already true, so it is not an error. The server
    /// refuses a guest, an unpublished guide, and a guide following themselves.
    func followInstructor(id: String, userID: UUID) async throws {
        struct Insert: Encodable {
            let userId: UUID
            let instructorId: String
            enum CodingKeys: String, CodingKey {
                case userId = "user_id", instructorId = "instructor_id"
            }
        }
        do {
            try await client
                .from("instructor_follows")
                .insert(Insert(userId: userID, instructorId: id))
                .execute()
        } catch let error as PostgrestError where error.code == "23505" {
            return
        }
    }

    /// Unfollows. Deleting a follow that isn't there is a no-op, not an error.
    func unfollowInstructor(id: String, userID: UUID) async throws {
        try await client
            .from("instructor_follows")
            .delete()
            .eq("user_id", value: userID)
            .eq("instructor_id", value: id)
            .execute()
    }

    // MARK: - Community

    /// The feed: finished practices, newest first, from the `community_activity`
    /// view. Pass `memberIDs` to narrow it to those people (the Friends
    /// filter); nil is everyone. The view runs with owner rights so it can
    /// see across members — it already leaves out journal prompts, unfinished
    /// sittings, guests and anyone who opted out. Uncached: it moves every
    /// time anyone finishes anything.
    func fetchCommunityActivity(memberIDs: [UUID]? = nil, limit: Int = 100) async throws -> [CommunityActivity] {
        if let memberIDs, memberIDs.isEmpty { return [] }
        var query = client
            .from("community_activity")
            .select()
        if let memberIDs {
            query = query.in("user_id", values: memberIDs)
        }
        let rows: [CommunityActivityRow] = try await query
            .order("completed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.compactMap(\.activity)
    }

    /// Specific members by id — the people behind a friendship row.
    func fetchCommunityMembers(ids: [UUID]) async throws -> [CommunityMember] {
        guard !ids.isEmpty else { return [] }
        let rows: [CommunityMemberRow] = try await client
            .from("community_members")
            .select()
            .in("id", values: ids)
            .limit(200)
            .execute()
            .value
        return rows.map(\.member)
    }

    /// Members whose name contains `query` — through `search_members()`, which
    /// matches on the full name server-side and answers with the abbreviated
    /// one. Two characters minimum; the function returns nothing for less.
    func searchMembers(_ query: String) async throws -> [CommunityMember] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let rows: [CommunityMemberRow] = try await client
            .rpc("search_members", params: ["q": trimmed])
            .execute()
            .value
        return rows.map(\.member)
    }

    /// Every friendship row this member is on either side of, pending or
    /// accepted, with the other person resolved. RLS returns only the caller's
    /// rows. Uncached.
    func fetchFriendships(userID: UUID) async throws -> [Friendship] {
        let rows: [FriendshipRow] = try await client
            .from("friendships")
            .select()
            .order("created_at", ascending: false)
            .limit(500)
            .execute()
            .value
        let others = Set(rows.map { $0.requesterId == userID ? $0.addresseeId : $0.requesterId })
        let members = try await fetchCommunityMembers(ids: Array(others))
        let byID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        return rows.map { row in
            let direction: Friendship.Direction = row.requesterId == userID ? .sent : .received
            return Friendship(requesterID: row.requesterId, addresseeID: row.addresseeId,
                              status: Friendship.Status(rawValue: row.status) ?? .pending,
                              createdAt: row.createdAt,
                              other: byID[direction == .sent ? row.addresseeId : row.requesterId],
                              direction: direction)
        }
    }

    /// Asks another member to be friends. The server refuses a guest, a
    /// request to a non-member, and a second row for the same pair.
    func sendFriendRequest(from userID: UUID, to memberID: UUID) async throws {
        struct Insert: Encodable {
            let requesterId: UUID
            let addresseeId: UUID
            enum CodingKeys: String, CodingKey {
                case requesterId = "requester_id", addresseeId = "addressee_id"
            }
        }
        try await client
            .from("friendships")
            .insert(Insert(requesterId: userID, addresseeId: memberID))
            .execute()
    }

    /// Accepts a request sent to this member. Only the addressee can, and only
    /// pending → accepted is a change the trigger lets through.
    func acceptFriendRequest(from requesterID: UUID, userID: UUID) async throws {
        struct Update: Encodable { let status: String }
        try await client
            .from("friendships")
            .update(Update(status: "accepted"))
            .eq("requester_id", value: requesterID)
            .eq("addressee_id", value: userID)
            .execute()
    }

    /// Declines, withdraws, or unfriends — one delete for all three. Either
    /// side may.
    func removeFriendship(between a: UUID, and b: UUID) async throws {
        try await client
            .from("friendships")
            .delete()
            .or("and(requester_id.eq.\(a.uuidString),addressee_id.eq.\(b.uuidString)),and(requester_id.eq.\(b.uuidString),addressee_id.eq.\(a.uuidString))")
            .execute()
    }

    // MARK: - Likes + notifications

    /// Likes one line of the feed. The server refuses a guest, a line that
    /// isn't in the feed, and the member's own line; a second like of the
    /// same line is a duplicate key, which the caller treats as "already".
    func likeActivity(playID: UUID, userID: UUID) async throws {
        struct Insert: Encodable {
            let playId: UUID
            let userId: UUID
            enum CodingKeys: String, CodingKey { case playId = "play_id", userId = "user_id" }
        }
        try await client
            .from("practice_play_likes")
            .insert(Insert(playId: playID, userId: userID))
            .execute()
    }

    func unlikeActivity(playID: UUID, userID: UUID) async throws {
        try await client
            .from("practice_play_likes")
            .delete()
            .eq("play_id", value: playID)
            .eq("user_id", value: userID)
            .execute()
    }

    /// This member's notifications, newest first. RLS scopes the view to the
    /// recipient. Uncached.
    func fetchNotifications(userID: UUID, limit: Int = 100) async throws -> [LikeNotification] {
        let rows: [NotificationRow] = try await client
            .from("member_notifications")
            .select()
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.map(\.notification)
    }

    /// Stamps every unread notification read. `read_at` latches server-side.
    func markNotificationsRead(userID: UUID) async throws {
        struct Update: Encodable {
            let readAt: Date
            enum CodingKeys: String, CodingKey { case readAt = "read_at" }
        }
        try await client
            .from("notifications")
            .update(Update(readAt: .now))
            .eq("user_id", value: userID)
            .is("read_at", value: nil)
            .execute()
    }

    // MARK: - Presence

    /// Every practice with at least 3 people present in the last 24 hours,
    /// keyed "session-4" / "journal-2" (the `PracticeProgress.id` shape).
    /// Uncached here — `PresenceStore` owns the freshness policy.
    func fetchPracticePresence() async throws -> [String: Presence] {
        let rows: [PracticePresenceRow] = try await client
            .rpc("practice_presence")
            .execute()
            .value
        return Dictionary(rows.map { ("\($0.contentKind)-\($0.contentId)", $0.presence) },
                          uniquingKeysWith: { a, _ in a })
    }

    /// Every published program with at least 3 members in flight, keyed by
    /// program id.
    func fetchProgramPresence() async throws -> [String: Presence] {
        let rows: [ProgramPresenceRow] = try await client
            .rpc("program_presence")
            .execute()
            .value
        return Dictionary(rows.map { ($0.programId, $0.presence) },
                          uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Push

    /// Registers (or refreshes) this device's APNs token for the signed-in
    /// member. Keyed on the token: the server-side trigger hands the token
    /// over from whoever held it before, so a shared phone follows the
    /// person signed in. The server refuses a guest.
    func registerDeviceToken(_ token: String, userID: UUID, environment: String) async throws {
        struct Upsert: Encodable {
            let token: String
            let userId: UUID
            let environment: String
            enum CodingKeys: String, CodingKey { case token, environment, userId = "user_id" }
        }
        try await client
            .from("device_tokens")
            .upsert(Upsert(token: token, userId: userID, environment: environment), onConflict: "token")
            .execute()
    }

    /// Forgets this device — on sign-out, so the next member's likes don't
    /// buzz the previous one's phone. RLS limits it to the caller's own row.
    func removeDeviceToken(_ token: String) async throws {
        try await client
            .from("device_tokens")
            .delete()
            .eq("token", value: token)
            .execute()
    }

    // MARK: - Avatar

    /// Uploads a new profile photo and points the profile at it. Returns the
    /// new `avatar_url`.
    ///
    /// A fresh uuid per upload, never an overwrite of a fixed name: the path IS
    /// the cache key in `RemoteImageCache` and in every other member's
    /// `URLCache`, so replacing the bytes behind the same path would leave the
    /// old face on screen until the caches turned over. The previous object is
    /// deleted best-effort once the row points away from it.
    func setAvatar(jpegData: Data, userID: UUID, replacing previous: String?) async throws -> String {
        let objectPath = "\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage
            .from("avatars")
            .upload(objectPath, data: jpegData,
                    options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg"))
        let avatarUrl = "avatars/\(objectPath)"
        try await updateAvatarUrl(avatarUrl, userID: userID)
        await removeAvatarObject(previous)
        return avatarUrl
    }

    /// Removes the profile photo: the row first, then the object.
    func clearAvatar(userID: UUID, previous: String?) async throws {
        try await updateAvatarUrl(nil, userID: userID)
        await removeAvatarObject(previous)
    }

    private func updateAvatarUrl(_ avatarUrl: String?, userID: UUID) async throws {
        struct Update: Encodable {
            let avatarUrl: String?
            enum CodingKeys: String, CodingKey { case avatarUrl = "avatar_url" }
            // Encode the nil explicitly, or PostgREST sees no change at all.
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(avatarUrl, forKey: .avatarUrl)
            }
        }
        try await client
            .from("profiles")
            .update(Update(avatarUrl: avatarUrl))
            .eq("id", value: userID)
            .execute()
    }

    /// Best-effort: an orphaned object costs a few kilobytes; a failed delete
    /// must not undo an upload that succeeded.
    private func removeAvatarObject(_ avatarUrl: String?) async {
        guard let avatarUrl, avatarUrl.hasPrefix("avatars/") else { return }
        let objectPath = String(avatarUrl.dropFirst("avatars/".count))
        do {
            _ = try await client.storage.from("avatars").remove(paths: [objectPath])
        } catch {
            Log.media.info("Old avatar not removed: \(error.localizedDescription)")
        }
    }

    /// The feed opt-out.
    func setShareActivity(_ share: Bool, userID: UUID) async throws {
        struct Update: Encodable {
            let shareActivity: Bool
            enum CodingKeys: String, CodingKey { case shareActivity = "share_activity" }
        }
        try await client
            .from("profiles")
            .update(Update(shareActivity: share))
            .eq("id", value: userID)
            .execute()
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
        instructorsCache = nil
        instructorsCacheDate = nil
        creditsCache = nil
        creditsCacheDate = nil
        writtenCache = nil
        writtenCacheDate = nil
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
    let avatarUrl: String?
    let shareActivity: Bool?

    enum CodingKeys: String, CodingKey {
        case id, email, intentions, frequency
        case fullName         = "full_name"
        case bodyState        = "body_state"
        case stripeCustomerId = "stripe_customer_id"
        case avatarUrl        = "avatar_url"
        case shareActivity    = "share_activity"
    }

    var profile: Profile {
        Profile(
            id: id,
            email: email ?? "",
            fullName: fullName ?? "",
            intentions: intentions ?? [],
            bodyState: bodyState ?? "",
            frequency: frequency ?? "",
            stripeCustomerId: stripeCustomerId,
            avatarUrl: avatarUrl,
            shareActivity: shareActivity ?? true
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
    /// Nullable since 0013 — a self-paced program has no calendar window.
    let dateRange: String?
    let days: Int
    let imageUrl: String
    let blurb: String?
    /// Decoded loosely, exactly like `RetreatRow.experience`, so one malformed
    /// curriculum can't take the whole catalog down with it.
    let curriculum: AnyJSON?
    let published: Bool
    /// Absent before 0019, so optional.
    let instructorId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, lead, days, blurb, curriculum, published
        case dateRange    = "date_range"
        case imageUrl     = "image_url"
        case instructorId = "instructor_id"
    }

    /// The curriculum document, or `nil` if there isn't one **or it's
    /// malformed**.
    ///
    /// Fails soft for the same reason the brochure does: this is content a
    /// human authors in the dashboard, and a missing comma must not blank the
    /// Programs tab. ⚠️ The cost is that a *broken* curriculum is
    /// indistinguishable on screen from an *unauthored* one — the program
    /// appears in the catalog and simply can't be started. When someone reports
    /// that, read the log before assuming the column is empty.
    var decodedCurriculum: ProgramCurriculum? {
        guard let curriculum, curriculum != .null else { return nil }
        do {
            let data = try JSONEncoder().encode(curriculum)
            // NOTE: a plain decoder, not `.convertFromSnakeCase`. The curriculum
            // types spell their own CodingKeys ("image_url", "content_id"), and
            // the two mechanisms together would look for "imageUrl" in a
            // document that says "image_url".
            return try JSONDecoder().decode(ProgramCurriculum.self, from: data)
        } catch {
            Log.data.error("Program \(self.id, privacy: .public) has an unreadable curriculum: \(error.localizedDescription)")
            return nil
        }
    }

    var program: Program {
        Program(id: id, title: title, lead: lead, when: dateRange, days: days,
                imageUrl: imageUrl, blurb: blurb, curriculum: decodedCurriculum,
                published: published, instructorID: instructorId)
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
    /// Absent before 0019, so optional.
    let instructorId: String?

    enum CodingKeys: String, CodingKey {
        case id, category, title, lead, blurb
        case mediaKind       = "media_kind"
        case storagePath     = "storage_path"
        case durationSeconds = "duration_seconds"
        case imageUrl        = "image_url"
        case instructorId    = "instructor_id"
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
            blurb: blurb ?? "",
            instructorID: instructorId
        )
    }
}


// MARK: - Written practice DTOs
//
// Columns are named rather than `*`, so a column added for the team's own use
// in the dashboard can't break the decode. `image_url` is nullable in the
// table — no photo draws `CatalogImage`'s gradient, which is what "" does.

/// Read model for `journal_prompts`.
private struct JournalPromptRow: Decodable {
    static let columns = "id, title, prompt, theme, image_url"

    let id: Int
    let title: String
    let prompt: String
    let theme: String
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, prompt, theme
        case imageUrl = "image_url"
    }

    var journalPrompt: JournalPrompt {
        JournalPrompt(id: id, title: title, prompt: prompt, theme: theme, imageUrl: imageUrl ?? "")
    }
}

/// Read model for `exercises`. The steps' shape is enforced by the table's
/// check constraint (0021), so a strict decode can't meet a malformed one.
private struct ExerciseRow: Decodable {
    static let columns = "id, title, focus, duration_seconds, image_url, blurb, steps"

    struct Step: Decodable {
        let name: String
        let detail: String?
    }

    let id: Int
    let title: String
    let focus: String
    let durationSeconds: Int
    let imageUrl: String?
    let blurb: String
    let steps: [Step]

    enum CodingKeys: String, CodingKey {
        case id, title, focus, blurb, steps
        case durationSeconds = "duration_seconds"
        case imageUrl        = "image_url"
    }

    var exercise: Exercise {
        Exercise(id: id, title: title, focus: focus, durationSeconds: durationSeconds,
                 imageUrl: imageUrl ?? "", blurb: blurb,
                 steps: steps.enumerated().map { index, step in
                     ExerciseStep(id: index + 1, name: step.name,
                                  detail: step.detail.flatMap { $0.isEmpty ? nil : $0 })
                 })
    }
}

/// Read model for `recipes`.
private struct RecipeRow: Decodable {
    static let columns = "id, title, angle, minutes, servings, image_url, blurb, ingredients, steps"

    let id: Int
    let title: String
    let angle: String
    let minutes: Int
    let servings: Int
    let imageUrl: String?
    let blurb: String
    let ingredients: [String]
    let steps: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, angle, minutes, servings, blurb, ingredients, steps
        case imageUrl = "image_url"
    }

    var recipe: Recipe {
        Recipe(id: id, title: title, angle: angle, minutes: minutes, servings: servings,
               imageUrl: imageUrl ?? "", blurb: blurb, ingredients: ingredients, steps: steps)
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

/// Read model for the four `practice_plays` columns `fetchPracticeLedger`
/// selects.
private struct PracticePlayRecordRow: Decodable {
    let clientEventId: UUID
    let contentKind: String
    let secondsPlayed: Int
    let completed: Bool
    let startedAt: Date

    enum CodingKeys: String, CodingKey {
        case completed
        case clientEventId = "client_event_id"
        case contentKind   = "content_kind"
        case secondsPlayed = "seconds_played"
        case startedAt     = "started_at"
    }

    /// Nil for a kind this build doesn't know. Unlike `PracticeProgressRow`,
    /// which falls back to `.session` so a resume card still has somewhere to
    /// go, a stat must not guess: counting an unknown kind as a class would
    /// inflate the number, and the check constraint means it can't happen
    /// today anyway.
    var record: PracticePlayRecord? {
        guard let kind = PracticeContentKind(rawValue: contentKind) else { return nil }
        return PracticePlayRecord(eventID: clientEventId, kind: kind,
                                  secondsPlayed: secondsPlayed, completed: completed,
                                  startedAt: startedAt)
    }
}

private struct ProgramEnrollmentRow: Decodable {
    let programId: String
    let enrolledAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case programId   = "program_id"
        case enrolledAt  = "enrolled_at"
        case completedAt = "completed_at"
    }

    var enrollment: ProgramEnrollment {
        ProgramEnrollment(programID: programId, enrolledAt: enrolledAt, completedAt: completedAt)
    }
}

private struct ProgramDayCompletionRow: Decodable {
    let programId: String
    let dayNumber: Int
    let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case programId   = "program_id"
        case dayNumber   = "day_number"
        case completedAt = "completed_at"
    }

    var completion: ProgramDayCompletion {
        ProgramDayCompletion(programID: programId, day: dayNumber, completedAt: completedAt)
    }
}

// MARK: - Community DTOs

/// Read model for the `community_members` view and `search_members()`.
private struct CommunityMemberRow: Decodable {
    let id: UUID
    let displayName: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl   = "avatar_url"
    }

    var member: CommunityMember {
        CommunityMember(id: id, displayName: displayName, avatarUrl: avatarUrl)
    }
}

/// Read model for one row of `practice_presence()`.
private struct PracticePresenceRow: Decodable {
    let contentKind: String
    let contentId: Int
    let present: Int
    let faces: [CommunityMemberRow]

    enum CodingKeys: String, CodingKey {
        case present, faces
        case contentKind = "content_kind"
        case contentId   = "content_id"
    }

    var presence: Presence { Presence(count: present, faces: faces.map(\.member)) }
}

/// Read model for one row of `program_presence()`.
private struct ProgramPresenceRow: Decodable {
    let programId: String
    let present: Int
    let faces: [CommunityMemberRow]

    enum CodingKeys: String, CodingKey {
        case present, faces
        case programId = "program_id"
    }

    var presence: Presence { Presence(count: present, faces: faces.map(\.member)) }
}

/// Read model for the `community_activity` view.
private struct CommunityActivityRow: Decodable {
    let playId: UUID
    let userId: UUID
    let displayName: String
    let avatarUrl: String?
    let contentKind: String
    let contentId: Int
    let contentTitle: String
    let category: String?
    let completedAt: Date
    /// Optional so a feed row from before 0016 still decodes.
    let likeCount: Int?
    let likedByMe: Bool?

    enum CodingKeys: String, CodingKey {
        case category
        case playId       = "play_id"
        case userId       = "user_id"
        case displayName  = "display_name"
        case avatarUrl    = "avatar_url"
        case contentKind  = "content_kind"
        case contentId    = "content_id"
        case contentTitle = "content_title"
        case completedAt  = "completed_at"
        case likeCount    = "like_count"
        case likedByMe    = "liked_by_me"
    }

    /// Nil for a kind this build doesn't know — a line that can't say what was
    /// practised is better left out than mislabelled.
    var activity: CommunityActivity? {
        guard let kind = PracticeContentKind(rawValue: contentKind) else { return nil }
        return CommunityActivity(
            id: playId,
            member: CommunityMember(id: userId, displayName: displayName, avatarUrl: avatarUrl),
            kind: kind,
            contentID: contentId,
            title: contentTitle,
            category: category.flatMap(PracticeCategory.init(rawValue:)),
            completedAt: completedAt,
            likeCount: likeCount ?? 0,
            likedByMe: likedByMe ?? false
        )
    }
}

/// Read model for the `member_notifications` view.
private struct NotificationRow: Decodable {
    let id: UUID
    let actorId: UUID?
    let actorName: String?
    let actorAvatarUrl: String?
    let playId: UUID?
    let contentTitle: String?
    let createdAt: Date
    let readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case actorId        = "actor_id"
        case actorName      = "actor_name"
        case actorAvatarUrl = "actor_avatar_url"
        case playId         = "play_id"
        case contentTitle   = "content_title"
        case createdAt      = "created_at"
        case readAt         = "read_at"
    }

    var notification: LikeNotification {
        LikeNotification(
            id: id,
            actor: actorId.map { CommunityMember(id: $0, displayName: actorName ?? "A member",
                                                 avatarUrl: actorAvatarUrl) },
            playID: playId,
            practiceTitle: contentTitle,
            createdAt: createdAt,
            readAt: readAt
        )
    }
}

private struct FriendshipRow: Decodable {
    let requesterId: UUID
    let addresseeId: UUID
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case createdAt   = "created_at"
    }
}

// MARK: - Instructor DTOs

/// Read model for `instructors`. Only the columns clients are granted.
private struct InstructorRow: Decodable {
    static let columns = "id, name, title, bio, photo_url"

    let id: String
    let name: String
    let title: String?
    let bio: String?
    let photoUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, title, bio
        case photoUrl = "photo_url"
    }

    var instructor: Instructor {
        Instructor(id: id, name: name,
                   title: title.flatMap { $0.isEmpty ? nil : $0 },
                   bio: bio.flatMap { $0.isEmpty ? nil : $0 },
                   photoUrl: photoUrl.flatMap { $0.isEmpty ? nil : $0 })
    }
}

/// Read model for one row of `instructor_social()`.
private struct InstructorSocialRow: Decodable {
    let followers: Int
    let following: Int
    let followedByMe: Bool
    let isMe: Bool
    let faces: [CommunityMemberRow]

    enum CodingKeys: String, CodingKey {
        case followers, following, faces
        case followedByMe = "followed_by_me"
        case isMe         = "is_me"
    }

    var social: InstructorSocial {
        InstructorSocial(followers: followers, following: following,
                         followedByMe: followedByMe, isMe: isMe,
                         faces: faces.map(\.member))
    }
}

/// Read model for `practice_credits`.
private struct PracticeCreditRow: Decodable {
    let contentKind: String
    let contentId: Int
    let instructorId: String

    enum CodingKeys: String, CodingKey {
        case contentKind  = "content_kind"
        case contentId    = "content_id"
        case instructorId = "instructor_id"
    }

    /// Nil for a kind this build doesn't know: better no credit than the
    /// wrong page's.
    var credit: PracticeCredit? {
        guard let kind = PracticeContentKind(rawValue: contentKind) else { return nil }
        return PracticeCredit(kind: kind, contentID: contentId, instructorID: instructorId)
    }
}
