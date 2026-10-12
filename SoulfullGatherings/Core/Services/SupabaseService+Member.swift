//
//  SupabaseService+Member.swift
//  Soulfull Gatherings
//
//  A member's own rows: digital retreat enrolments, their profile and photo,
//  bookings, and the practice ledger. Never cached.
//

import Foundation
@preconcurrency import Supabase

extension SupabaseService {

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

    /// Leaves a program: the enrolment and every day completion for it, in
    /// one transaction (`leave_program`, 0031).
    ///
    /// It was two requests, and when the second failed the server kept the
    /// enrolment with its days cleared: still joined, Day 1 open since the
    /// original join date, and every practice finished since completing it
    /// again. "Begin again" then restarted on that half-cleared slate.
    ///
    /// Note what is **not** deleted — `practice_plays`. The practices were
    /// genuinely done and their creators genuinely earned from them; leaving a
    /// program is the member withdrawing from a schedule, not rewriting
    /// history. Re-joining later starts the days again from an empty slate,
    /// which is the point. The member is the caller (`auth.uid()` under RLS).
    func leaveProgram(id programID: String) async throws {
        try await client
            .rpc("leave_program", params: ["p_program_id": programID])
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
    ///
    /// An empty name is left out of the write, so the row keeps the name it
    /// has: a phone that doesn't know the member's name has nothing to say
    /// about it. Sending it blank wiped members' names (onboarding committed
    /// the name it hadn't asked a member for).
    func upsertProfile(_ profile: Profile) async throws {
        let name = MemberName.limited(profile.fullName)
        let payload = ProfileUpsert(
            id: profile.id,
            fullName: name.isEmpty ? nil : name,
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
        return rows.compactMap(\.progress)
    }

    /// Every sitting this member has recorded — the raw ledger rows rather than
    /// the per-practice aggregate — reduced to the columns the You tab's
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
                .select("client_event_id, content_kind, seconds_played, completed, started_at, completed_at")
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

    /// Gives a profile that lost its name its name back
    /// (`AuthManager.reconcileName`). Never called with an empty name.
    func setProfileName(_ name: String, userID: UUID) async throws {
        struct Update: Encodable {
            let fullName: String
            enum CodingKeys: String, CodingKey { case fullName = "full_name" }
        }
        try await client
            .from("profiles")
            .update(Update(fullName: MemberName.limited(name)))
            .eq("id", value: userID)
            .execute()
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
}

// MARK: - Member DTOs

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
    /// Nil leaves the key out, so the upsert doesn't touch the column.
    let fullName: String?
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
    /// Since 0029. Optional so a database without it still decodes.
    let lastCompletedAt: Date?

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
        case lastCompletedAt    = "last_completed_at"
    }

    /// Nil for a kind this build doesn't know. It used to fall back to
    /// `.session`, so once a newer library shipped, an older build read that
    /// library's #4 and Breathwork's #4 as the same practice — two rows with
    /// one key, which `PracticeProgressStore` built its map from and trapped
    /// on, every launch, until the member updated. A resume card for a
    /// practice this build can't open has nowhere to go anyway.
    var progress: PracticeProgress? {
        guard let kind = PracticeContentKind(rawValue: contentKind) else { return nil }
        return PracticeProgress(
            kind: kind,
            contentID: contentId,
            title: contentTitle,
            creator: creator,
            category: category.flatMap(PracticeCategory.init(rawValue:)),
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            totalSecondsPlayed: totalSecondsPlayed,
            completed: completed,
            playCount: playCount,
            lastPlayedAt: lastPlayedAt,
            // Without 0029's column, the last open stands in for the last
            // finish — the rule the app ran on before it. With it, a finished
            // practice always has one (0029 backfilled them).
            lastCompletedAt: lastCompletedAt ?? (completed ? lastPlayedAt : nil)
        )
    }
}

/// Read model for the `practice_plays` columns `fetchPracticeLedger` selects.
private struct PracticePlayRecordRow: Decodable {
    let clientEventId: UUID
    let contentKind: String
    let secondsPlayed: Int
    let completed: Bool
    let startedAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case completed
        case clientEventId = "client_event_id"
        case contentKind   = "content_kind"
        case secondsPlayed = "seconds_played"
        case startedAt     = "started_at"
        case completedAt   = "completed_at"
    }

    /// Nil for a kind this build doesn't know, as in `PracticeProgressRow`: a
    /// stat must not guess, and counting an unknown kind as a class would
    /// inflate the number.
    var record: PracticePlayRecord? {
        guard let kind = PracticeContentKind(rawValue: contentKind) else { return nil }
        return PracticePlayRecord(eventID: clientEventId, kind: kind,
                                  secondsPlayed: secondsPlayed, completed: completed,
                                  startedAt: startedAt, completedAt: completedAt)
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
