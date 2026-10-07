//
//  GuideDashboardViewModel.swift
//  Soulfull Gatherings
//
//  A guide's own numbers: who practiced with them, what each past month's
//  pool paid them, and what this month is worth so far (0026). Shown only to
//  a member whose account the team has linked to a guide. For everyone else
//  `guide_dashboard()` answers no row and nothing appears.
//
//  The You tab owns one of these and hands it to the dashboard sheet, so the
//  card and the sheet always show the same read.
//

import Foundation

@Observable @MainActor
final class GuideDashboardViewModel {

    /// Nil until a read says this account is a guide, and after one says it
    /// isn't.
    private(set) var dashboard: GuideDashboard?
    /// A read has answered at least once since the last reset. Until then
    /// "no dashboard" means "not known yet", not "not a guide".
    private(set) var hasLoaded = false
    /// The last read failed. The figures already on screen stay: a failed
    /// reload never swaps them for an error.
    private(set) var failure: ProfileLoadFailure?
    private(set) var isLoading = false

    private let fetch: @Sendable () async throws -> GuideDashboard?
    /// Bumped by `reset()`, so a read that started for the previous person
    /// can't land on the next one's screen.
    private var generation = 0

    init(fetch: @escaping @Sendable () async throws -> GuideDashboard? = {
        try await SupabaseService.shared.fetchGuideDashboard()
    }) {
        self.fetch = fetch
    }

    /// Whose figures these are: the You tab's identity key (user id and
    /// whether they have an account).
    private var owner: String?

    var isGuide: Bool { dashboard != nil }

    /// Reads for `owner`, dropping what an earlier person left first. The tab's
    /// `.task` runs again every time it comes back; for the same person that
    /// re-reads over the card already showing instead of blanking it.
    func load(for owner: String) async {
        if owner != self.owner {
            reset()
            self.owner = owner
        }
        await load()
    }

    /// Reads for whoever is here now: pull to refresh, Try again, opening the
    /// sheet.
    func load() async {
        #if DEBUG
        if Self.isPreview {
            dashboard = Self.previewFixture()
            hasLoaded = true
            return
        }
        #endif
        let started = generation
        isLoading = true
        defer { if generation == started { isLoading = false } }
        do {
            let result = try await fetch()
            guard generation == started else { return }
            dashboard = result
            failure = nil
            hasLoaded = true
        } catch where error.isCancellation {
            return
        } catch {
            guard generation == started else { return }
            Log.data.info("Guide dashboard unavailable: \(error.localizedDescription)")
            failure = ProfileLoadFailure(offline: error.isOffline)
        }
    }

    /// Everything that belonged to whoever was signed in.
    func reset() {
        generation += 1
        owner = nil
        dashboard = nil
        hasLoaded = false
        failure = nil
        isLoading = false
    }

    // MARK: - Preview fixture

    /// `-preview-guide`: a deterministic dashboard, relative to this UTC
    /// month, so `GuideDashboardTests` can assert exact figures without a
    /// guide account. Pair it with `-preview-you` for the member layout.
    /// Always false in Release.
    static var isPreview: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-preview-guide")
        #else
        false
        #endif
    }

    #if DEBUG
    /// - This month: 86 people, 1,203 minutes heard of 9,700 (12.4%), a
    ///   $2,500.00 pool set, so an estimate of $310.05.
    /// - Last month: paid, $284.09. Two months ago: closed and due, $198.40.
    ///   Three months ago: no pool set yet. Four months ago: paid, $96.05.
    ///   Paid to date: $380.14. Every amount is the pool times the share,
    ///   rounded down, as the server works it out.
    /// - `-preview-guide-pending` leaves this month's pool unset instead.
    static func previewFixture() -> GuideDashboard {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = PayoutMonth.utc
        let now = utc.dateComponents([.year, .month], from: .now)
        let thisMonth = PayoutMonth(year: now.year!, month: now.month!)
        let pending = CommandLine.arguments.contains("-preview-guide-pending")

        func usd(_ cents: Int) -> PayoutAmount { PayoutAmount(cents: cents, currency: "usd") }
        func paid(_ month: PayoutMonth) -> Date { utc.date(byAdding: .day, value: 3, to: month.advanced(by: 1).start)! }
        func month(_ back: Int, people: Int, minutes: Int, of total: Int, pool: Int?, earned: Int?,
                   paid isPaid: Bool = false) -> GuideMonth {
            let m = thisMonth.advanced(by: -back)
            return GuideMonth(month: m, people: people, plays: people * 2, completions: people,
                              secondsHeard: minutes * 60, poolSeconds: total * 60,
                              pool: pool.map(usd), earned: earned.map(usd),
                              paidAt: isPaid ? paid(m) : nil)
        }

        return GuideDashboard(
            instructorID: "alma-guerra",
            name: "Alma Guerra",
            photoUrl: "instructor-photos/alma-guerra.jpg",
            thisMonth: thisMonth,
            totals: .init(people: 212, plays: 640, completions: 301, secondsHeard: 4_918 * 60),
            months: [
                month(0, people: 86, minutes: 1_203, of: 9_700,
                      pool: pending ? nil : 250_000, earned: pending ? nil : 31_005),
                month(1, people: 74, minutes: 1_050, of: 9_240, pool: 250_000, earned: 28_409, paid: true),
                month(2, people: 51, minutes: 1_120, of: 11_290, pool: 200_000, earned: 19_840),
                month(3, people: 33, minutes: 960, of: 7_400, pool: nil, earned: nil),
                month(4, people: 12, minutes: 585, of: 6_090, pool: 100_000, earned: 9_605, paid: true),
            ],
            practices: [
                GuidePracticeStat(kind: .session, contentID: 4, title: "Breath of Fire", people: 141,
                                  peopleThisMonth: 38, plays: 300, completions: 180, secondsHeard: 2_760 * 60),
                GuidePracticeStat(kind: .session, contentID: 7, title: "Body Scan for Sleep", people: 96,
                                  peopleThisMonth: 31, plays: 210, completions: 90, secondsHeard: 2_158 * 60),
                GuidePracticeStat(kind: .exercise, contentID: 2, title: "Morning Mobility", people: 40,
                                  peopleThisMonth: 9, plays: 80, completions: 25, secondsHeard: 0),
                GuidePracticeStat(kind: .journal, contentID: 3, title: "What am I holding?", people: 18,
                                  peopleThisMonth: 0, plays: 22, completions: 6, secondsHeard: 0),
            ],
            programs: [
                GuideProgramStat(id: "finding-ground", title: "Finding Ground", joined: 34, finished: 12),
            ])
    }
    #endif
}
