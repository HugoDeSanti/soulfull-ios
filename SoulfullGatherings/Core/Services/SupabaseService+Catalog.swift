//
//  SupabaseService+Catalog.swift
//  Soulfull Gatherings
//
//  The catalog: retreats, digital retreats, practice tracks, the written
//  libraries and guides. Readable by a guest, never written by a client,
//  and the only reads `CatalogCache` keeps.
//

import SwiftUI
@preconcurrency import Supabase

extension SupabaseService {

    // MARK: - Retreats, digital retreats and practice tracks

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
        try await catalog.value(.retreats) { [client] in
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            // UTC, not the device's zone. `start_date` is a bare Postgres
            // `date`, so formatting "today" locally made the catalog disagree
            // with itself across time zones — a user in UTC+13 lost a retreat
            // starting today, one in UTC−11 kept seeing one that had begun.
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
            return rows.map(\.retreat)
        }
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
        try await catalog.value(.programs) { [client] in
            let rows: [ProgramRow] = try await client
                .from("programs")
                .select()
                // Draft programs stay invisible, so a curriculum can be authored
                // in the dashboard over several sittings without appearing
                // half-built.
                .eq("published", value: true)
                .order("sort_order", ascending: true, nullsFirst: false)
                .order("title", ascending: true)
                .limit(50)
                .execute()
                .value
            return rows.map(\.program)
        }
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
        struct CategoryRow: Decodable { let category: String }
        do {
            let set = try await catalog.value(.practiceCategories) { [client] in
                let rows: [CategoryRow] = try await client
                    .from("practice_sessions")
                    .select("category")
                    // Program-only media must not light up a Practice track
                    // the user can then open and find empty.
                    .eq("program_only", value: false)
                    .limit(500)
                    .execute()
                    .value
                return Set(rows.compactMap { PracticeCategory(rawValue: $0.category) })
            }
            return .known(set)
        } catch {
            // Not cached, so it re-checks on the next visit.
            Log.data.info("Practice availability unknown: \(error.localizedDescription)")
            return .unknown
        }
    }

    /// Sessions for one practice track, newest-friendly ordering by title.
    func fetchPracticeSessions(category: PracticeCategory) async throws -> [PracticeSession] {
        try await catalog.value(.practice(category)) { [client] in
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
            return rows.map(\.session)
        }
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
        try await catalog.value(.writtenLibrary) { [client] in
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
            return try await WrittenLibrary(journals: journals.map(\.journalPrompt),
                                            exercises: exercises.map(\.exercise),
                                            recipes: recipes.map(\.recipe))
        }
    }

    // MARK: - Instructors

    /// Every published guide, in the team's order. Cached like the rest of the
    /// catalog.
    ///
    /// The columns are named rather than `*`: `user_id` is withheld from client
    /// roles by column grant (0019), and PostgREST answers a `*` over a column
    /// you may not read with 42501 rather than leaving it out.
    func fetchInstructors() async throws -> [Instructor] {
        try await catalog.value(.instructors) { [client] in
            let rows: [InstructorRow] = try await client
                .from("instructors")
                .select(InstructorRow.columns)
                .eq("published", value: true)
                .order("sort_order", ascending: true, nullsFirst: false)
                .order("name", ascending: true)
                .limit(100)
                .execute()
                .value
            return rows.map(\.instructor)
        }
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
    /// Practice-tab sessions, and the written practices that name them.
    /// `program_only` media is left out — it belongs to its program and is
    /// reached from there, the same line the Practice tab draws. Uncached,
    /// except for the written libraries, which are catalog and taken whole
    /// from their cache rather than queried per guide.
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
        // Throws with the rest: a guide known only for written practices would
        // otherwise read as having published nothing.
        let written = try await fetchWrittenLibrary()
        return InstructorLibrary(programs: programRows.map(\.program),
                                 sessions: sessionRows.map(\.session),
                                 written: written,
                                 instructorID: id)
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
}

// MARK: - Catalog DTOs

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
    static let columns = "id, title, prompt, theme, image_url, instructor_id"

    let id: Int
    let title: String
    let prompt: String
    let theme: String
    let imageUrl: String?
    let instructorId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, prompt, theme
        case imageUrl     = "image_url"
        case instructorId = "instructor_id"
    }

    var journalPrompt: JournalPrompt {
        JournalPrompt(id: id, title: title, prompt: prompt, theme: theme, imageUrl: imageUrl ?? "",
                      instructorID: instructorId)
    }
}

/// Read model for `exercises`. The steps' shape is enforced by the table's
/// check constraint (0021), so a strict decode can't meet a malformed one.
private struct ExerciseRow: Decodable {
    static let columns = "id, title, focus, duration_seconds, image_url, blurb, steps, instructor_id"

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
    let instructorId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, focus, blurb, steps
        case durationSeconds = "duration_seconds"
        case imageUrl        = "image_url"
        case instructorId    = "instructor_id"
    }

    var exercise: Exercise {
        Exercise(id: id, title: title, focus: focus, durationSeconds: durationSeconds,
                 imageUrl: imageUrl ?? "", blurb: blurb,
                 steps: steps.enumerated().map { index, step in
                     ExerciseStep(id: index + 1, name: step.name,
                                  detail: step.detail.flatMap { $0.isEmpty ? nil : $0 })
                 },
                 instructorID: instructorId)
    }
}

/// Read model for `recipes`.
private struct RecipeRow: Decodable {
    static let columns = "id, title, angle, minutes, servings, image_url, blurb, ingredients, steps, instructor_id"

    let id: Int
    let title: String
    let angle: String
    let minutes: Int
    let servings: Int
    let imageUrl: String?
    let blurb: String
    let ingredients: [String]
    let steps: [String]
    let instructorId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, angle, minutes, servings, blurb, ingredients, steps
        case imageUrl     = "image_url"
        case instructorId = "instructor_id"
    }

    var recipe: Recipe {
        Recipe(id: id, title: title, angle: angle, minutes: minutes, servings: servings,
               imageUrl: imageUrl ?? "", blurb: blurb, ingredients: ingredients, steps: steps,
               instructorID: instructorId)
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
