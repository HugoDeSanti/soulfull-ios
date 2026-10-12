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

/// Why a member is being reported (0028, `report-member`). The raw values are
/// `member_reports.reason`, and the titles are what the team's email says —
/// the Edge Function holds the same strings, so change both together.
enum ReportReason: String, CaseIterable, Identifiable, Hashable, Sendable, Encodable {
    case photo, name, harassment, spam, other

    var id: String { rawValue }

    var title: String {
        switch self {
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
    let reason: ReportReason
    /// The reporter's note, trimmed; nil when they wrote nothing.
    let details: String?

    /// The longest note the sheet takes (the server caps at 1,000).
    static let maxDetails = 500

    /// Nil until a reason is chosen — the one thing a report can't do without.
    init?(reportedID: UUID, playID: UUID?, reason: ReportReason?, details: String) {
        guard let reason else { return nil }
        self.reportedID = reportedID
        self.playID = playID
        self.reason = reason
        let note = String(details.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxDetails))
        self.details = note.isEmpty ? nil : note
    }

    enum CodingKeys: String, CodingKey {
        case reportedID = "reported_id", playID = "play_id", reason, details
    }
}
