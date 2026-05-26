import Foundation
import Supabase

final class SupabaseService: Sendable {
    static let shared = SupabaseService()

    private let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }

    func fetchRetreats() async throws -> [Retreat] {
        let rows: [RetreatRow] = try await client
            .from("retreats")
            .select()
            .execute()
            .value
        return rows.map(\.retreat)
    }

    func fetchPrograms() async throws -> [Program] {
        let rows: [ProgramRow] = try await client
            .from("programs")
            .select()
            .execute()
            .value
        return rows.map(\.program)
    }

}

// MARK: - DTOs

private struct RetreatRow: Codable {
    let id: String
    let name: String
    let country: String
    let startDate: String   // "yyyy-MM-dd" from Postgres date column
    let endDate: String
    let maxGuests: Int
    let priceUsd: Int
    let tags: [String]
    let blurb: String
    let imageUrl: String

    enum CodingKeys: String, CodingKey {
        case id, name, country, tags, blurb
        case imageUrl  = "image_url"
        case startDate = "start_date"
        case endDate   = "end_date"
        case maxGuests = "max_guests"
        case priceUsd  = "price_usd"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var retreat: Retreat {
        let start = Self.dateFormatter.date(from: startDate) ?? Date()
        let end   = Self.dateFormatter.date(from: endDate)   ?? Date()
        return Retreat(
            id: id, name: name, country: country,
            startDate: start, endDate: end,
            maxGuests: maxGuests, priceUsd: priceUsd,
            tags: tags, blurb: blurb, imageUrl: imageUrl
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
