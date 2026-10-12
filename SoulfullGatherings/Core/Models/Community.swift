//
//  Community.swift
//  Soulfull Gatherings
//
//  Other members as the Community tab shows them: the feed, friends,
//  likes, presence, and reports.
//

import Foundation

// MARK: - Community

/// Another member as the Community tab shows them: an id, a name abbreviated
/// server-side ("Hugo D." — the full name never leaves the row), and a photo.
/// Read from the `community_members` view and `search_members()`.
struct CommunityMember: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    /// `avatars/<id>/<uuid>.jpg`, resolved by `ImageSource`; nil for initials.
    let avatarUrl: String?
}

/// "75.7k present" — how many people are with a practice or a digital
/// retreat, and up to three of their faces. From `practice_presence()` /
/// `program_presence()` (0018).
///
/// For a practice, present = started it in the last 24 hours. For a program,
/// = joined, not finished, and active in it in the last 14 days. The server
/// never answers below 3 people, puts friends first among the faces, leaves
/// out the viewer and anyone who opted out of sharing, and sends no faces for
/// a journal prompt — so `faces` may hold fewer than three, or none.
struct Presence: Hashable, Sendable {
    let count: Int
    let faces: [CommunityMember]

    /// "840 present", "1.2k present", "75.7k present", "1.1M present".
    var label: String { "\(Self.compact(count)) present" }

    /// Rounded DOWN to one decimal, so the line never claims someone who
    /// isn't there: 1,999 reads "1.9k", not "2k".
    static func compact(_ n: Int) -> String {
        func scaled(_ unit: Int, _ suffix: String) -> String {
            let tenths = n / (unit / 10)
            let whole = tenths / 10, rest = tenths % 10
            return rest == 0 ? "\(whole)\(suffix)" : "\(whole).\(rest)\(suffix)"
        }
        switch n {
        case ..<1_000:     return "\(n)"
        case ..<1_000_000: return scaled(1_000, "k")
        default:           return scaled(1_000_000, "M")
        }
    }
}

/// One line of the feed: a member finished a practice. Read from the
/// `community_activity` view, which already excludes journal prompts, anything
/// unfinished, and members who have opted out.
struct CommunityActivity: Identifiable, Hashable, Sendable {
    /// The play's id — one row per sitting, so a session done twice is two lines.
    let id: UUID
    let member: CommunityMember
    let kind: PracticeContentKind
    let contentID: Int
    let title: String
    let category: PracticeCategory?
    let completedAt: Date
    /// How many members liked this line, and whether the viewer is one of
    /// them. Both come from the view per request, so the likes table itself
    /// stays scoped to the people it concerns.
    var likeCount: Int = 0
    var likedByMe: Bool = false

    /// The eyebrow under the line: the track for a session, the library otherwise.
    var kindLabel: String {
        if let category { return category.title }
        switch kind {
        case .session:  return "Session"
        case .exercise: return "Movement"
        case .recipe:   return "Recipe"
        case .journal:  return "Journal"
        }
    }
}

/// A friend request, or the friendship it became. `status` is the server's;
/// which side of it *this* member is on is `direction`.
struct Friendship: Identifiable, Hashable, Sendable {
    enum Status: String, Hashable, Sendable { case pending, accepted }
    enum Direction: Hashable, Sendable {
        /// This member asked.
        case sent
        /// This member was asked.
        case received
    }

    let requesterID: UUID
    let addresseeID: UUID
    let status: Status
    let createdAt: Date
    /// The other person, resolved through `community_members`. Nil only if
    /// they have since deleted their account (the row cascades soon after).
    var other: CommunityMember?
    let direction: Direction

    var id: String { "\(requesterID.uuidString)-\(addresseeID.uuidString)" }
    var otherID: UUID { direction == .sent ? addresseeID : requesterID }
    var isAccepted: Bool { status == .accepted }
}

/// Where a member stands relative to me, for the button beside their name.
enum FriendStanding: Hashable {
    case none
    case requested
    case awaitingMyAnswer
    case friends
}

// MARK: - A friend's practice

/// A day on the calendar, with no time and no zone: a `date` as
/// `friend_practice_stats()` answers it ("2026-10-12"), counted in the zone
/// the app asked for.
struct CalendarDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// "YYYY-MM-DD", or nil for anything else.
    init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day `date` falls on in `calendar`.
    init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Its first moment in `calendar`, as `startOfDay` gives it.
    func start(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
            .map(calendar.startOfDay(for:))
    }

    static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

/// A friend's practice in numbers, from `friend_practice_stats()` (0034): only
/// a friend who shares their practice, and only this. Never which practices,
/// and never a calendar: the days of their latest run are its first and last.
/// The You tab's rules count every figure (`PracticeStats`), so a friend sees
/// the numbers the member sees on their own You tab.
struct FriendPractice: Hashable, Sendable {
    let memberID: UUID
    /// Their latest run of consecutive practice days. Nil until they finish a
    /// first practice.
    let latestRun: ClosedRange<CalendarDay>?
    /// The longest run they've ever had.
    let longestRun: Int
    /// Finished sessions and movement sittings.
    let classesTaken: Int
    /// Time spent in those, finished or not.
    let minutesPracticed: Int

    /// Their streak as of `now`. The latest run counts while it reaches today
    /// or yesterday, by `PracticeStreak`, the rule the You tab uses, so it
    /// moves at midnight with no new read.
    func streak(calendar: Calendar = .current, now: Date) -> PracticeStreak {
        var days = Set<Date>()
        if let run = latestRun, var cursor = run.lowerBound.start(in: calendar),
           let last = run.upperBound.start(in: calendar) {
            // Bounded, so a malformed run can't spin: no run is 100 years long.
            while cursor <= last, days.count < 36_525 {
                days.insert(cursor)
                guard let next = PracticeStreak.step(cursor, by: 1, calendar) else { break }
                cursor = next
            }
        }
        let streak = PracticeStreak(days: days, calendar: calendar, now: now)
        return PracticeStreak(current: streak.current, best: max(longestRun, streak.best),
                              keptToday: streak.keptToday)
    }

    /// When they last finished a practice, said for their streak's caption:
    /// "Practiced today", "Last practiced yesterday", "Last practiced
    /// Monday", "Last practiced 3 Oct". Nil if they never have.
    func lastPracticedLabel(calendar: Calendar = .current, now: Date) -> String? {
        guard let last = latestRun?.upperBound.start(in: calendar) else { return nil }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        switch days {
        case ...0: return "Practiced today"
        case 1:    return "Last practiced yesterday"
        default:
            var style = Date.FormatStyle.dateTime
            style.timeZone = calendar.timeZone
            let when = days < 7 ? last.formatted(style.weekday(.wide))
                                : last.formatted(style.day().month(.abbreviated))
            return "Last practiced \(when)"
        }
    }

    /// The line under a friend's name on the Friends screen: "12-day streak ·
    /// 48 classes", "48 classes" between streaks, "No practices finished yet".
    func summary(calendar: Calendar = .current, now: Date) -> String {
        let current = streak(calendar: calendar, now: now).current
        let classes = classesTaken == 1 ? "1 class" : "\(classesTaken.formatted()) classes"
        switch (current > 0, classesTaken > 0) {
        case (true, true):   return "\(current)-day streak · \(classes)"
        case (true, false):  return "\(current)-day streak"
        case (false, true):  return classes
        case (false, false): return latestRun == nil ? "No practices finished yet" : "No streak right now"
        }
    }
}

/// Where a friend's numbers stand on this screen.
enum FriendPracticeStanding: Equatable {
    /// Not read yet.
    case loading
    case shared(FriendPractice)
    /// They have "Share my practice" off, so there is nothing to show.
    case keptPrivate
    /// The read failed, and there is nothing from earlier to show instead.
    case unavailable(CommunityLoadFailure)
}

/// "Alma G. liked your Confidence Boost practice." Read from the
/// `member_notifications` view; written only by the like trigger.
struct LikeNotification: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Nil once the liker has deleted their account: "Someone liked…".
    let actor: CommunityMember?
    let playID: UUID?
    let practiceTitle: String?
    let createdAt: Date
    let readAt: Date?

    var isUnread: Bool { readAt == nil }
}

/// Why a member or a comment is being reported (0028, 0032, `report-member`).
/// The raw values are `member_reports.reason`, and the titles are what the
/// team's email says — the Edge Function holds the same strings, so change
/// both together.
enum ReportReason: String, CaseIterable, Identifiable, Hashable, Sendable, Encodable {
    case photo, name, harassment, spam, other
    /// For a comment (0032).
    case offensive

    var id: String { rawValue }

    /// What the sheet offers when the report is about the member themselves.
    static let aboutAMember: [ReportReason] = [.photo, .name, .harassment, .spam, .other]
    /// …and when it is about something they wrote.
    static let aboutAComment: [ReportReason] = [.offensive, .harassment, .spam, .other]

    var title: String {
        switch self {
        case .offensive:  "Hateful or offensive"
        case .photo:      "Inappropriate photo"
        case .name:       "Offensive name"
        case .harassment: "Harassment or unwanted contact"
        case .spam:       "Spam or a fake account"
        case .other:      "Something else"
        }
    }
}

/// One report, as the Report sheet sends it to `report-member`. Who is
/// reporting comes from the session's JWT, never from here.
struct MemberReport: Encodable, Hashable, Sendable {
    let reportedID: UUID
    /// The feed line it was reported from, if any.
    let playID: UUID?
    /// The comment it is about, if any (0032).
    let commentID: UUID?
    let reason: ReportReason
    /// The reporter's note, trimmed; nil when they wrote nothing.
    let details: String?

    /// The longest note the sheet takes (the server caps at 1,000).
    static let maxDetails = 500

    /// Nil until a reason is chosen — the one thing a report can't do without.
    init?(reportedID: UUID, playID: UUID?, commentID: UUID? = nil, reason: ReportReason?, details: String) {
        guard let reason else { return nil }
        self.reportedID = reportedID
        self.playID = playID
        self.commentID = commentID
        self.reason = reason
        let note = String(details.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxDetails))
        self.details = note.isEmpty ? nil : note
    }

    enum CodingKeys: String, CodingKey {
        case reportedID = "reported_id", playID = "play_id", commentID = "comment_id", reason, details
    }
}
