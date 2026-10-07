//
//  GuideDashboardTests.swift
//  SoulfullTests
//
//  A guide's dashboard (0026). Months are UTC months and roll over the year
//  correctly; a month shows an amount only once its pool is set, and says
//  whether that amount is an estimate, owed or paid; the chart's months run
//  to this one with quiet months as zeros; the JSON `guide_dashboard()`
//  writes maps onto the model; and a reload never blanks figures already on
//  screen, nor lands on the next person's.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Guide dashboard")
struct GuideDashboardTests {

    private static let october = PayoutMonth(year: 2026, month: 10)

    private static func month(_ month: PayoutMonth, seconds: Int = 0, poolSeconds: Int = 0,
                              poolCents: Int? = nil, earnedCents: Int? = nil,
                              paidAt: Date? = nil, people: Int = 0) -> GuideMonth {
        GuideMonth(month: month, people: people, plays: 0, completions: 0,
                   secondsHeard: seconds, poolSeconds: poolSeconds,
                   pool: poolCents.map { PayoutAmount(cents: $0, currency: "usd") },
                   earned: earnedCents.map { PayoutAmount(cents: $0, currency: "usd") },
                   paidAt: paidAt)
    }

    private static func dashboard(thisMonth: PayoutMonth = october, months: [GuideMonth]) -> GuideDashboard {
        GuideDashboard(instructorID: "alma-guerra", name: "Alma Guerra", photoUrl: nil,
                       thisMonth: thisMonth,
                       totals: .init(people: 0, plays: 0, completions: 0, secondsHeard: 0),
                       months: months, practices: [], programs: [])
    }

    // MARK: - Months

    @Test("A month parses from the server's first-of-month date")
    func monthParses() {
        let month = PayoutMonth(isoDate: "2026-10-01")

        #expect(month == Self.october)
    }

    @Test("A malformed month is refused", arguments: ["", "2026-13-01", "2026-00-01", "October"])
    func malformedMonthRefused(raw: String) {
        #expect(PayoutMonth(isoDate: raw) == nil)
    }

    @Test("Stepping across a new year lands in the right year and month")
    func monthsRollOverTheYear() {
        let january = PayoutMonth(year: 2027, month: 1)

        #expect(january.advanced(by: -1) == PayoutMonth(year: 2026, month: 12))
        #expect(january.advanced(by: -13) == PayoutMonth(year: 2025, month: 12))
        #expect(PayoutMonth(year: 2026, month: 11).advanced(by: 3) == PayoutMonth(year: 2027, month: 2))
    }

    @Test("A month starts at midnight UTC and is named in UTC")
    func monthIsUTC() {
        let locale = Locale(identifier: "en_US")

        #expect(Self.october.start == Calendar.gregorian(in: "UTC").at(2026, 10, 1))
        #expect(Self.october.title(locale: locale) == "October 2026")
        #expect(Self.october.shortName(locale: locale) == "Oct")
    }

    // MARK: - Where a month's money stands

    enum Expected: String, CaseIterable { case estimate, awaitingPool, due, paid }

    @Test("A month's standing", arguments: [
        // (months back from this one, pool set, paid, expected)
        (0, true,  false, Expected.estimate),
        (0, false, false, Expected.awaitingPool),
        (1, false, false, Expected.awaitingPool),
        (1, true,  false, Expected.due),
        (1, true,  true,  Expected.paid),
        (0, true,  true,  Expected.paid),
    ])
    func standing(back: Int, poolSet: Bool, paid: Bool, expected: Expected) {
        let month = Self.month(Self.october.advanced(by: -back), seconds: 600, poolSeconds: 6_000,
                               poolCents: poolSet ? 100_000 : nil, earnedCents: poolSet ? 10_000 : nil,
                               paidAt: paid ? Calendar.gregorian(in: "UTC").at(2026, 10, 3) : nil)

        let standing = month.standing(thisMonth: Self.october)

        switch (standing, expected) {
        case (.estimate(let a), .estimate), (.due(let a), .due), (.paid(let a, _), .paid):
            #expect(a == PayoutAmount(cents: 10_000, currency: "usd"))
        case (.awaitingPool, .awaitingPool):
            break
        default:
            Issue.record("Expected \(expected), got \(standing)")
        }
    }

    @Test("A month's share is its seconds over every guide's, and unknown when nobody was heard")
    func share() {
        let heard = Self.month(Self.october, seconds: 1_203 * 60, poolSeconds: 9_700 * 60)
        let silent = Self.month(Self.october)

        #expect(abs((heard.share ?? 0) - 0.124020) < 0.000_001)
        #expect(silent.share == nil)
    }

    @Test("Money is formatted from cents in its own currency")
    func amountFormatting() {
        let amount = PayoutAmount(cents: 31_005, currency: "usd")

        #expect(amount.formatted(locale: Locale(identifier: "en_US")) == "$310.05")
    }

    // MARK: - The dashboard's derived figures

    @Test("The chart's months run to this one, oldest first, with zeros before the first play")
    func recentMonthsPadded() {
        let feb = PayoutMonth(year: 2027, month: 2)
        let board = Self.dashboard(thisMonth: feb, months: [
            Self.month(feb, people: 9),
            Self.month(feb.advanced(by: -1), people: 4),
        ])

        let recent = board.recentMonths(6)

        #expect(recent.map(\.month) == (0..<6).reversed().map { feb.advanced(by: -$0) })
        #expect(recent.map(\.people) == [0, 0, 0, 0, 4, 9])
        #expect(recent.first?.month == PayoutMonth(year: 2026, month: 9))
    }

    @Test("This month is a zero month when the server didn't send it, never last month's figures")
    func currentFallsBackToEmpty() {
        let board = Self.dashboard(months: [Self.month(Self.october.advanced(by: -1), seconds: 600, people: 40)])

        #expect(board.current.month == Self.october)
        #expect(board.current.people == 0)
        #expect(board.pastMonths.count == 1)
    }

    @Test("Paid to date adds up only the months that were paid")
    func paidToDate() {
        let paidOn = Calendar.gregorian(in: "UTC").at(2026, 9, 3)
        let board = Self.dashboard(months: [
            Self.month(Self.october, poolCents: 250_000, earnedCents: 31_005),
            Self.month(Self.october.advanced(by: -1), poolCents: 250_000, earnedCents: 28_409, paidAt: paidOn),
            Self.month(Self.october.advanced(by: -2), poolCents: 200_000, earnedCents: 19_840),
            Self.month(Self.october.advanced(by: -3), poolCents: 100_000, earnedCents: 9_605, paidAt: paidOn),
        ])

        #expect(board.paidToDate == PayoutAmount(cents: 38_014, currency: "usd"))
    }

    @Test("Paid to date is nothing to show when nothing was paid, or the currencies differ")
    func paidToDateAbsent() {
        let paidOn = Calendar.gregorian(in: "UTC").at(2026, 9, 3)
        let unpaid = Self.dashboard(months: [Self.month(Self.october, poolCents: 1_000, earnedCents: 500)])
        let mixed = Self.dashboard(months: [
            Self.month(Self.october.advanced(by: -1), poolCents: 1_000, earnedCents: 500, paidAt: paidOn),
            GuideMonth(month: Self.october.advanced(by: -2), people: 0, plays: 0, completions: 0,
                       secondsHeard: 0, poolSeconds: 0,
                       pool: PayoutAmount(cents: 1_000, currency: "eur"),
                       earned: PayoutAmount(cents: 500, currency: "eur"), paidAt: paidOn),
        ])

        #expect(unpaid.paidToDate == nil)
        #expect(mixed.paidToDate == nil)
    }

    // MARK: - What guide_dashboard() answers

    /// Shaped exactly as the SQL writes it: `to_jsonb` of each CTE row, bigint
    /// counts as numbers, a date as "YYYY-MM-DD", timestamptz with and
    /// without fractional seconds.
    private static let payload = """
    [{"dashboard": {
      "instructor_id": "alma-guerra", "name": "Alma Guerra", "photo_url": "",
      "this_month": "2026-10-01",
      "totals": {"people": 212, "plays": 640, "completions": 301, "seconds_heard": 295080},
      "months": [
        {"month": "2026-08-01", "people": 51, "plays": 90, "completions": 40, "seconds_heard": 67200,
         "pool_seconds": 677400, "pool_cents": 200000, "currency": "usd",
         "paid_at": "2026-09-03T09:00:00+00:00", "earned_cents": 19840},
        {"month": "2026-10-01", "people": 86, "plays": 172, "completions": 86, "seconds_heard": 72180,
         "pool_seconds": 582000, "pool_cents": null, "currency": null, "paid_at": null, "earned_cents": null},
        {"month": "2026-09-01", "people": 74, "plays": 148, "completions": 74, "seconds_heard": 0,
         "pool_seconds": 0, "pool_cents": 250000, "currency": "usd",
         "paid_at": "2026-10-03T09:00:00.123456+00:00", "earned_cents": null}
      ],
      "practices": [
        {"content_kind": "session", "content_id": 4, "title": "Breath of Fire", "people": 141,
         "people_this_month": 38, "plays": 300, "completions": 180, "seconds_heard": 165600},
        {"content_kind": "massage", "content_id": 1, "title": "Retired", "people": 2,
         "people_this_month": 0, "plays": 2, "completions": 0, "seconds_heard": 0}
      ],
      "programs": [{"id": "finding-ground", "title": "Finding Ground", "joined": 34, "finished": 12}]
    }}]
    """

    @Test("The function's JSON maps onto the dashboard")
    func decodesPayload() throws {
        let board = try #require(try SupabaseService.decodeGuideDashboard(Data(Self.payload.utf8)))

        #expect(board.instructorID == "alma-guerra")
        #expect(board.photoUrl == nil)
        #expect(board.thisMonth == Self.october)
        #expect(board.totals.minutesHeard == 4_918)
        #expect(board.months.map(\.month) == [Self.october, Self.october.advanced(by: -1),
                                               Self.october.advanced(by: -2)])
        #expect(board.current.standing(thisMonth: board.thisMonth) == .awaitingPool)
        #expect(board.months.last?.paidAt == Calendar.gregorian(in: "UTC").at(2026, 9, 3, 9))
        #expect(board.programs == [GuideProgramStat(id: "finding-ground", title: "Finding Ground",
                                                    joined: 34, finished: 12)])
    }

    @Test("A set pool with none of the guide's minutes in it is a zero, not an unknown")
    func setPoolWithNoMinutesIsZero() throws {
        let board = try #require(try SupabaseService.decodeGuideDashboard(Data(Self.payload.utf8)))
        let september = try #require(board.months.first { $0.month == Self.october.advanced(by: -1) })

        #expect(september.earned == PayoutAmount(cents: 0, currency: "usd"))
        #expect(september.paidAt != nil)
    }

    @Test("A practice of a kind this build doesn't know is left off, never shown as a session")
    func unknownKindDropped() throws {
        let board = try #require(try SupabaseService.decodeGuideDashboard(Data(Self.payload.utf8)))

        #expect(board.practices.map(\.id) == ["session-4"])
    }

    @Test("No row means this account isn't a guide")
    func noRowIsNotAGuide() throws {
        #expect(try SupabaseService.decodeGuideDashboard(Data("[]".utf8)) == nil)
    }
}

// MARK: - Loading

@MainActor
@Suite("Guide dashboard loading")
struct GuideDashboardLoadingTests {

    /// A stand-in for `guide_dashboard()`.
    @MainActor
    final class Server {
        var answer: GuideDashboard?
        var failure: Error?
        /// Holds the next read at its start.
        var holdNextRead = false
        private(set) var heldRead: CheckedContinuation<Void, Never>?

        func read() async throws -> GuideDashboard? {
            let answer = self.answer
            let failure = self.failure
            if holdNextRead {
                holdNextRead = false
                await withCheckedContinuation { heldRead = $0 }
            }
            if let failure { throw failure }
            return answer
        }

        func releaseRead() { heldRead?.resume(); heldRead = nil }

        func waitForHeldRead() async {
            while heldRead == nil { await Task.yield() }
        }
    }

    private static func board(people: Int) -> GuideDashboard {
        let october = PayoutMonth(year: 2026, month: 10)
        return GuideDashboard(instructorID: "alma-guerra", name: "Alma Guerra", photoUrl: nil,
                              thisMonth: october,
                              totals: .init(people: people, plays: 0, completions: 0, secondsHeard: 0),
                              months: [], practices: [], programs: [])
    }

    private func model(_ server: Server) -> GuideDashboardViewModel {
        GuideDashboardViewModel(fetch: { try await server.read() })
    }

    @Test("A member who isn't a guide has no dashboard, and that is an answer")
    func notAGuide() async {
        let server = Server()
        let vm = model(server)

        await vm.load(for: "member")

        #expect(vm.dashboard == nil)
        #expect(vm.hasLoaded)
        #expect(vm.failure == nil)
    }

    @Test("A linked guide gets their dashboard")
    func guideLoads() async {
        let server = Server()
        server.answer = Self.board(people: 86)
        let vm = model(server)

        await vm.load(for: "guide")

        #expect(vm.isGuide)
        #expect(vm.dashboard?.totals.people == 86)
    }

    @Test("A failed reload keeps the figures on screen and says why", arguments: [true, false])
    func failedReloadKeepsFigures(offline: Bool) async {
        let server = Server()
        server.answer = Self.board(people: 86)
        let vm = model(server)
        await vm.load(for: "guide")

        server.failure = offline ? URLError(.notConnectedToInternet) : URLError(.badServerResponse)
        await vm.load()

        #expect(vm.dashboard?.totals.people == 86)
        #expect(vm.failure == (offline ? .offline : .failed))
    }

    @Test("Coming back to the tab re-reads over the card instead of blanking it")
    func sameOwnerKeepsCardWhileReading() async {
        let server = Server()
        server.answer = Self.board(people: 86)
        let vm = model(server)
        await vm.load(for: "guide")

        server.answer = Self.board(people: 90)
        server.holdNextRead = true
        let reload = Task { await vm.load(for: "guide") }
        await server.waitForHeldRead()

        #expect(vm.dashboard?.totals.people == 86)

        server.releaseRead()
        await reload.value
        #expect(vm.dashboard?.totals.people == 90)
    }

    @Test("A read that started for the last person never lands on the next one's screen")
    func staleReadDiscarded() async {
        let server = Server()
        server.answer = Self.board(people: 86)
        server.holdNextRead = true
        let vm = model(server)
        let guideRead = Task { await vm.load(for: "guide") }
        await server.waitForHeldRead()

        server.answer = nil
        vm.reset()
        await vm.load(for: "next-member")
        server.releaseRead()
        await guideRead.value

        #expect(vm.dashboard == nil)
        #expect(vm.hasLoaded)
    }
}
