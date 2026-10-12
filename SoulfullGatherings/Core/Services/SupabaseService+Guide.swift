//
//  SupabaseService+Guide.swift
//  Soulfull Gatherings
//
//  A linked guide's own figures (`guide_dashboard()`, 0026).
//

import Foundation
@preconcurrency import Supabase

extension SupabaseService {

    // MARK: - Guide dashboard

    /// The caller's own numbers as a guide, through `guide_dashboard()` (0026).
    /// Nil for anyone whose account the team hasn't linked to a guide, which
    /// is every member and every guest. Uncached: it's member data, and this
    /// month's figure moves with every play.
    func fetchGuideDashboard() async throws -> GuideDashboard? {
        let response = try await client
            .rpc("guide_dashboard")
            .execute()
        return try Self.decodeGuideDashboard(response.data)
    }

    /// What `guide_dashboard()` answers, decoded with the decoder PostgREST's
    /// own `.value` uses. Static, so the mapping from the function's JSON is
    /// tested against the exact keys the SQL writes, with no network.
    nonisolated static func decodeGuideDashboard(_ data: Data) throws -> GuideDashboard? {
        let rows = try PostgrestClient.Configuration.jsonDecoder.decode([GuideDashboardRow].self, from: data)
        return rows.first?.dashboard.model
    }
}

// MARK: - Guide dashboard DTOs

/// Read model for one row of `guide_dashboard()`: a single jsonb column.
private struct GuideDashboardRow: Decodable {
    let dashboard: GuideDashboardPayload
}

private struct GuideDashboardPayload: Decodable {
    let instructorId: String
    let name: String
    let photoUrl: String?
    let thisMonth: String
    let totals: Totals
    let months: [Month]
    let practices: [Practice]
    let programs: [ProgramStat]

    enum CodingKeys: String, CodingKey {
        case name, totals, months, practices, programs
        case instructorId = "instructor_id"
        case photoUrl     = "photo_url"
        case thisMonth    = "this_month"
    }

    struct Totals: Decodable {
        let people: Int
        let plays: Int
        let completions: Int
        let secondsHeard: Int

        enum CodingKeys: String, CodingKey {
            case people, plays, completions
            case secondsHeard = "seconds_heard"
        }
    }

    struct Month: Decodable {
        let month: String
        let people: Int
        let plays: Int
        let completions: Int
        let secondsHeard: Int
        let poolSeconds: Int
        let poolCents: Int?
        let currency: String?
        let paidAt: Date?
        let earnedCents: Int?

        enum CodingKeys: String, CodingKey {
            case month, people, plays, completions, currency
            case secondsHeard = "seconds_heard"
            case poolSeconds  = "pool_seconds"
            case poolCents    = "pool_cents"
            case paidAt       = "paid_at"
            case earnedCents  = "earned_cents"
        }

        var model: GuideMonth? {
            guard let payoutMonth = PayoutMonth(isoDate: month) else { return nil }
            let currency = (currency ?? "usd").lowercased()
            let pool = poolCents.map { PayoutAmount(cents: $0, currency: currency) }
            // A set pool with none of their minutes in it is a zero, which the
            // server says too; this only guards the two from disagreeing.
            let earned = pool.map { PayoutAmount(cents: earnedCents ?? 0, currency: $0.currency) }
            return GuideMonth(month: payoutMonth, people: people, plays: plays,
                              completions: completions, secondsHeard: secondsHeard,
                              poolSeconds: poolSeconds, pool: pool, earned: earned,
                              paidAt: pool == nil ? nil : paidAt)
        }
    }

    struct Practice: Decodable {
        let contentKind: String
        let contentId: Int
        let title: String
        let people: Int
        let peopleThisMonth: Int
        let plays: Int
        let completions: Int
        let secondsHeard: Int

        enum CodingKeys: String, CodingKey {
            case title, people, plays, completions
            case contentKind     = "content_kind"
            case contentId       = "content_id"
            case peopleThisMonth = "people_this_month"
            case secondsHeard    = "seconds_heard"
        }

        /// Nil for a kind this build doesn't know. It's left off the list
        /// rather than shown as a session: an unknown kind read as `.session`
        /// is how a play gets credited to the wrong library (CLAUDE.md).
        var model: GuidePracticeStat? {
            guard let kind = PracticeContentKind(rawValue: contentKind) else { return nil }
            return GuidePracticeStat(kind: kind, contentID: contentId, title: title, people: people,
                                     peopleThisMonth: peopleThisMonth, plays: plays,
                                     completions: completions, secondsHeard: secondsHeard)
        }
    }

    struct ProgramStat: Decodable {
        let id: String
        let title: String
        let joined: Int
        let finished: Int
    }

    var model: GuideDashboard? {
        guard let thisMonth = PayoutMonth(isoDate: thisMonth) else { return nil }
        return GuideDashboard(
            instructorID: instructorId,
            name: name,
            photoUrl: photoUrl.flatMap { $0.isEmpty ? nil : $0 },
            thisMonth: thisMonth,
            totals: .init(people: totals.people, plays: totals.plays,
                          completions: totals.completions, secondsHeard: totals.secondsHeard),
            months: months.compactMap(\.model).sorted { $0.month > $1.month },
            practices: practices.compactMap(\.model),
            programs: programs.map { GuideProgramStat(id: $0.id, title: $0.title,
                                                      joined: $0.joined, finished: $0.finished) })
    }
}
