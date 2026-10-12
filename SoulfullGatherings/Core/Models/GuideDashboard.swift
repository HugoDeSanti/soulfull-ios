//
//  GuideDashboard.swift
//  Soulfull Gatherings
//
//  What a guide linked to an account sees of their own reach and
//  earnings (`guide_dashboard()`, 0026).
//

import Foundation

// MARK: - Guide dashboard

/// A calendar month in UTC: the month a play, a pool and a payout are counted
/// in (0026), so a play belongs to one month wherever it was heard. Labelled
/// in UTC too: formatted in the device's zone, "2026-10-01" is still September
/// anywhere west of Greenwich.
struct PayoutMonth: Hashable, Comparable, Sendable {
    let year: Int
    /// 1–12.
    let month: Int

    init(year: Int, month: Int) {
        // Normalised, so stepping back from January lands in December.
        let (years, months) = (year * 12 + (month - 1)).quotientAndRemainder(dividingBy: 12)
        self.year = months < 0 ? years - 1 : years
        self.month = (months < 0 ? months + 12 : months) + 1
    }

    /// The server's shape for a month: its first day, "2026-10-01".
    init?(isoDate: String) {
        let parts = isoDate.prefix(10).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]),
              (1...12).contains(month) else { return nil }
        self.init(year: year, month: month)
    }

    static func < (a: PayoutMonth, b: PayoutMonth) -> Bool {
        (a.year, a.month) < (b.year, b.month)
    }

    func advanced(by months: Int) -> PayoutMonth {
        PayoutMonth(year: year, month: month + months)
    }

    static let utc = TimeZone(identifier: "UTC")!

    /// Midnight UTC on its first day.
    var start: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    private func formatted(_ style: (Date.FormatStyle) -> Date.FormatStyle, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: Self.utc)
        return start.formatted(style(base))
    }

    /// "October 2026".
    func title(locale: Locale = .current) -> String {
        formatted({ $0.month(.wide).year() }, locale: locale)
    }

    /// "October".
    func name(locale: Locale = .current) -> String {
        formatted({ $0.month(.wide) }, locale: locale)
    }

    /// "Oct", under a bar.
    func shortName(locale: Locale = .current) -> String {
        formatted({ $0.month(.abbreviated) }, locale: locale)
    }
}

/// Money in its minor unit, in its own currency: what a pool or a payout is
/// stored as, so nothing is rounded before it's shown.
struct PayoutAmount: Hashable, Sendable {
    let cents: Int
    /// Lowercase ISO 4217, as stored ("usd").
    let currency: String

    func formatted(locale: Locale = .current) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currency.uppercased()).locale(locale))
    }
}

/// One month of a guide's numbers, from `guide_dashboard()`.
///
/// `people`, `plays` and `completions` count everything of theirs anyone
/// opened. `secondsHeard` counts their sessions only: it is what the pool is
/// shared by, and the written libraries take no part in payouts
/// (`creditsCreator`). Their own plays are in none of these.
struct GuideMonth: Identifiable, Hashable, Sendable {
    let month: PayoutMonth
    let people: Int
    let plays: Int
    let completions: Int
    let secondsHeard: Int
    /// Every guide's seconds heard that month: the denominator of the share.
    let poolSeconds: Int
    /// The month's pool, once the team has set it.
    let pool: PayoutAmount?
    /// Their cut of `pool`. Nil exactly when the pool is.
    let earned: PayoutAmount?
    let paidAt: Date?

    var id: PayoutMonth { month }

    var minutesHeard: Int { secondsHeard / 60 }

    /// Their share of every guide's minutes heard, 0–1. Nil when no guide's
    /// sessions were heard at all: there's nothing to have a share of.
    var share: Double? {
        poolSeconds > 0 ? min(1, Double(secondsHeard) / Double(poolSeconds)) : nil
    }

    /// A month with nothing in it: before their first play, or a quiet one.
    static func empty(_ month: PayoutMonth) -> GuideMonth {
        GuideMonth(month: month, people: 0, plays: 0, completions: 0, secondsHeard: 0,
                   poolSeconds: 0, pool: nil, earned: nil, paidAt: nil)
    }

    /// Where a month's money stands. "Not set" and "not paid" call for different
    /// words: the first has no figure at all, the second has one that is owed.
    enum Standing: Hashable {
        /// The month is still running and its pool is set: what the share so
        /// far would be worth. It moves until the month closes.
        case estimate(PayoutAmount)
        /// No pool entered for this month yet, running or past. No figure is
        /// shown: there is nothing honest to multiply the share by.
        case awaitingPool
        /// Closed, with a pool, and not paid out yet.
        case due(PayoutAmount)
        case paid(PayoutAmount, on: Date)
    }

    /// `thisMonth` is the server's running month, not the device's.
    func standing(thisMonth: PayoutMonth) -> Standing {
        guard let earned else { return .awaitingPool }
        if let paidAt { return .paid(earned, on: paidAt) }
        return month >= thisMonth ? .estimate(earned) : .due(earned)
    }
}

/// One practice of a guide's that someone opened, all time.
struct GuidePracticeStat: Identifiable, Hashable, Sendable {
    let kind: PracticeContentKind
    let contentID: Int
    /// The title it was last played under.
    let title: String
    let people: Int
    let peopleThisMonth: Int
    let plays: Int
    let completions: Int
    /// Sessions only; zero for the written libraries, which aren't heard.
    let secondsHeard: Int

    var id: String { "\(kind.rawValue)-\(contentID)" }
}

/// A digital retreat a guide leads. `joined` counts current enrolments:
/// leaving a program removes the row (0013).
struct GuideProgramStat: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let joined: Int
    let finished: Int
}

/// Everything on a guide's dashboard, for the member whose account the team
/// linked to them (`instructors.user_id`). Aggregates only: no member is ever
/// named or counted on their own.
struct GuideDashboard: Hashable, Sendable {
    struct Totals: Hashable, Sendable {
        let people: Int
        let plays: Int
        let completions: Int
        let secondsHeard: Int

        var minutesHeard: Int { secondsHeard / 60 }
    }

    let instructorID: String
    let name: String
    let photoUrl: String?
    /// The running month on the server's clock (UTC).
    let thisMonth: PayoutMonth
    let totals: Totals
    /// Newest first, from the month of their first play to `thisMonth`, quiet
    /// months included.
    let months: [GuideMonth]
    /// Most people first.
    let practices: [GuidePracticeStat]
    let programs: [GuideProgramStat]

    /// This month so far. The server always sends it; a zero month stands in
    /// if it ever doesn't, rather than last month's figures under this
    /// month's name.
    var current: GuideMonth {
        months.first { $0.month == thisMonth } ?? .empty(thisMonth)
    }

    /// Closed months, newest first.
    var pastMonths: [GuideMonth] {
        months.filter { $0.month < thisMonth }
    }

    /// The last `count` months up to this one, oldest first, for the chart.
    /// Months before their first play are filled with zeros, so a new guide's
    /// chart has its full width rather than one bar stretched across it.
    func recentMonths(_ count: Int) -> [GuideMonth] {
        let byMonth = Dictionary(months.map { ($0.month, $0) }, uniquingKeysWith: { a, _ in a })
        return (0..<max(count, 0)).reversed().map { back in
            let month = thisMonth.advanced(by: -back)
            return byMonth[month] ?? .empty(month)
        }
    }

    /// Everything paid out so far. Nil when nothing has been, and when the
    /// paid months are in more than one currency (no honest single sum).
    var paidToDate: PayoutAmount? {
        let paid = months.compactMap { $0.paidAt == nil ? nil : $0.earned }
        guard let currency = paid.first?.currency,
              paid.allSatisfy({ $0.currency == currency }) else { return nil }
        return PayoutAmount(cents: paid.reduce(0) { $0 + $1.cents }, currency: currency)
    }
}
