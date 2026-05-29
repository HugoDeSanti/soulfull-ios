import SwiftUI
@preconcurrency import Supabase

/// Singleton data layer. Implemented as an `actor` so its mutable cache is
/// safe to access from concurrent async contexts without explicit locking.
actor SupabaseService {

    static let shared: SupabaseService = {
        do {
            return try SupabaseService()
        } catch {
            fatalError("""
                [SupabaseService] \(error)
                Copy Config/Secrets.xcconfig.example → Config/Secrets.xcconfig and fill in your values.
                """)
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
    private let cacheTTL: TimeInterval = 300

    private init() throws {
        let config = try SupabaseConfig.make()
        client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
    }

    // MARK: - Fetches

    func fetchRetreats() async throws -> [Retreat] {
        if let cache = retreatsCache,
           let date = retreatsCacheDate,
           Date().timeIntervalSince(date) < cacheTTL {
            return cache
        }
        let rows: [RetreatRow] = try await client
            .from("retreats")
            .select()
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

    /// Resolves a private Storage object path into a time-limited playable URL.
    /// Media in a *public* bucket can skip this and use its permanent URL.
    func signedMediaURL(path: String,
                        bucket: String = "practice-media",
                        expiresIn: Int = 3600) async throws -> URL {
        try await client.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: expiresIn)
    }

    func invalidateCache() {
        retreatsCache = nil
        retreatsCacheDate = nil
        programsCache = nil
        programsCacheDate = nil
        practiceCache.removeAll()
        practiceCacheDate.removeAll()
    }
}

// MARK: - DTOs

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

    enum CodingKeys: String, CodingKey {
        case id, name, country, tags, blurb
        case imageUrl  = "image_url"
        case startDate = "start_date"
        case endDate   = "end_date"
        case maxGuests = "max_guests"
        case priceUsd  = "price_usd"
        case toneTop   = "tone_top"
        case toneMid   = "tone_mid"
        case toneBase  = "tone_base"
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
            toneBase: Color(hex: toneBase)
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
