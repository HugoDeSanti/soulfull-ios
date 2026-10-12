//
//  SupabaseService+Community.swift
//  Soulfull Gatherings
//
//  Other members: the feed, friends, Report and Block, likes and the bell,
//  presence, and push tokens.
//

import Foundation
@preconcurrency import Supabase

extension SupabaseService {

    // MARK: - Community

    /// The feed: finished practices, newest first, from the `community_activity`
    /// view. Pass `memberIDs` to narrow it to those people (the Friends
    /// filter); nil is everyone. The view runs with owner rights so it can
    /// see across members — it already leaves out journal prompts, unfinished
    /// sittings, guests and anyone who opted out. Uncached: it moves every
    /// time anyone finishes anything.
    func fetchCommunityActivity(memberIDs: [UUID]? = nil, limit: Int = 100) async throws -> [CommunityActivity] {
        if let memberIDs, memberIDs.isEmpty { return [] }
        var query = client
            .from("community_activity")
            .select()
        if let memberIDs {
            query = query.in("user_id", values: memberIDs)
        }
        let rows: [CommunityActivityRow] = try await query
            .order("completed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.compactMap(\.activity)
    }

    /// Specific members by id — the people behind a friendship row.
    func fetchCommunityMembers(ids: [UUID]) async throws -> [CommunityMember] {
        guard !ids.isEmpty else { return [] }
        let rows: [CommunityMemberRow] = try await client
            .from("community_members")
            .select()
            .in("id", values: ids)
            .limit(200)
            .execute()
            .value
        return rows.map(\.member)
    }

    /// Members whose name contains `query` — through `search_members()`, which
    /// matches on the full name server-side and answers with the abbreviated
    /// one. Two characters minimum; the function returns nothing for less.
    func searchMembers(_ query: String) async throws -> [CommunityMember] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let rows: [CommunityMemberRow] = try await client
            .rpc("search_members", params: ["q": trimmed])
            .execute()
            .value
        return rows.map(\.member)
    }

    /// Every friendship row this member is on either side of, pending or
    /// accepted, with the other person resolved. RLS returns only the caller's
    /// rows. Uncached.
    func fetchFriendships(userID: UUID) async throws -> [Friendship] {
        let rows: [FriendshipRow] = try await client
            .from("friendships")
            .select()
            .order("created_at", ascending: false)
            .limit(500)
            .execute()
            .value
        let others = Set(rows.map { $0.requesterId == userID ? $0.addresseeId : $0.requesterId })
        let members = try await fetchCommunityMembers(ids: Array(others))
        let byID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        return rows.map { row in
            let direction: Friendship.Direction = row.requesterId == userID ? .sent : .received
            return Friendship(requesterID: row.requesterId, addresseeID: row.addresseeId,
                              status: Friendship.Status(rawValue: row.status) ?? .pending,
                              createdAt: row.createdAt,
                              other: byID[direction == .sent ? row.addresseeId : row.requesterId],
                              direction: direction)
        }
    }

    /// Asks another member to be friends. The server refuses a guest, a
    /// request to a non-member, and a second row for the same pair.
    func sendFriendRequest(from userID: UUID, to memberID: UUID) async throws {
        struct Insert: Encodable {
            let requesterId: UUID
            let addresseeId: UUID
            enum CodingKeys: String, CodingKey {
                case requesterId = "requester_id", addresseeId = "addressee_id"
            }
        }
        try await client
            .from("friendships")
            .insert(Insert(requesterId: userID, addresseeId: memberID))
            .execute()
    }

    /// Accepts a request sent to this member. Only the addressee can, and only
    /// pending → accepted is a change the trigger lets through.
    func acceptFriendRequest(from requesterID: UUID, userID: UUID) async throws {
        struct Update: Encodable { let status: String }
        try await client
            .from("friendships")
            .update(Update(status: "accepted"))
            .eq("requester_id", value: requesterID)
            .eq("addressee_id", value: userID)
            .execute()
    }

    /// Declines, withdraws, or unfriends — one delete for all three. Either
    /// side may.
    func removeFriendship(between a: UUID, and b: UUID) async throws {
        try await client
            .from("friendships")
            .delete()
            .or("and(requester_id.eq.\(a.uuidString),addressee_id.eq.\(b.uuidString)),and(requester_id.eq.\(b.uuidString),addressee_id.eq.\(a.uuidString))")
            .execute()
    }

    // MARK: - Safety (0028)

    /// The members this member has blocked, newest first, through
    /// `blocked_members()` — they're out of `community_members` for the
    /// blocker, so the You tab's list needs its own read. Uncached.
    func fetchBlockedMembers() async throws -> [CommunityMember] {
        let rows: [CommunityMemberRow] = try await client
            .rpc("blocked_members")
            .execute()
            .value
        return rows.map(\.member)
    }

    /// Blocks a member. The server ends any friendship or request between
    /// them, removes their likes on each other's practices, and from then on
    /// leaves each out of everything the other reads. A block that already
    /// exists is a duplicate key, and the thing asked for is already true.
    func blockMember(_ memberID: UUID, userID: UUID) async throws {
        struct Insert: Encodable {
            let blockerId: UUID
            let blockedId: UUID
            enum CodingKeys: String, CodingKey { case blockerId = "blocker_id", blockedId = "blocked_id" }
        }
        do {
            try await client
                .from("member_blocks")
                .insert(Insert(blockerId: userID, blockedId: memberID))
                .execute()
        } catch let error as PostgrestError where error.code == "23505" {
            return
        }
    }

    /// Unblocks. What the block removed (a friendship, likes) stays removed.
    func unblockMember(_ memberID: UUID, userID: UUID) async throws {
        try await client
            .from("member_blocks")
            .delete()
            .eq("blocker_id", value: userID)
            .eq("blocked_id", value: memberID)
            .execute()
    }

    /// Files a report with the team through the `report-member` Edge Function,
    /// which stores it and emails the monitored inbox. Never retried here, for
    /// the reason `sendRetreatEnquiry` isn't: the sheet offers the retry.
    func reportMember(_ report: MemberReport) async throws {
        struct ReportResult: Decodable { let reported: Bool }
        let result: ReportResult = try await client.functions.invoke(
            "report-member",
            options: FunctionInvokeOptions(body: report)
        )
        guard result.reported else { throw AppError.unknown }
    }

    // MARK: - Likes + notifications

    /// Likes one line of the feed. The server refuses a guest, a line that
    /// isn't in the feed, and the member's own line; a second like of the
    /// same line is a duplicate key, which the caller treats as "already".
    func likeActivity(playID: UUID, userID: UUID) async throws {
        struct Insert: Encodable {
            let playId: UUID
            let userId: UUID
            enum CodingKeys: String, CodingKey { case playId = "play_id", userId = "user_id" }
        }
        try await client
            .from("practice_play_likes")
            .insert(Insert(playId: playID, userId: userID))
            .execute()
    }

    func unlikeActivity(playID: UUID, userID: UUID) async throws {
        try await client
            .from("practice_play_likes")
            .delete()
            .eq("play_id", value: playID)
            .eq("user_id", value: userID)
            .execute()
    }

    /// This member's notifications, newest first. RLS scopes the view to the
    /// recipient. Uncached.
    func fetchNotifications(userID: UUID, limit: Int = 100) async throws -> [LikeNotification] {
        let rows: [NotificationRow] = try await client
            .from("member_notifications")
            .select()
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.map(\.notification)
    }

    /// Stamps these notifications read — the ones the Notifications screen has
    /// shown, never "everything unread", which also stamped a like that arrived
    /// after the list was read, so it never showed as new. `read_at` latches
    /// server-side. `member_notifications.id` is `notifications.id` (0016).
    func markNotificationsRead(userID: UUID, ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        struct Update: Encodable {
            let readAt: Date
            enum CodingKeys: String, CodingKey { case readAt = "read_at" }
        }
        try await client
            .from("notifications")
            .update(Update(readAt: .now))
            .eq("user_id", value: userID)
            .in("id", values: ids)
            .is("read_at", value: nil)
            .execute()
    }

    // MARK: - Presence

    /// Every practice with at least 3 people present in the last 24 hours,
    /// keyed "session-4" / "journal-2" (the `PracticeProgress.id` shape).
    /// Uncached here — `PresenceStore` owns the freshness policy.
    func fetchPracticePresence() async throws -> [String: Presence] {
        let rows: [PracticePresenceRow] = try await client
            .rpc("practice_presence")
            .execute()
            .value
        return Dictionary(rows.map { ("\($0.contentKind)-\($0.contentId)", $0.presence) },
                          uniquingKeysWith: { a, _ in a })
    }

    /// Every published program with at least 3 members in flight, keyed by
    /// program id.
    func fetchProgramPresence() async throws -> [String: Presence] {
        let rows: [ProgramPresenceRow] = try await client
            .rpc("program_presence")
            .execute()
            .value
        return Dictionary(rows.map { ($0.programId, $0.presence) },
                          uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Push

    /// Registers (or refreshes) this device's APNs token for the signed-in
    /// member. Keyed on the token: the server-side trigger hands the token
    /// over from whoever held it before, so a shared phone follows the
    /// person signed in. The server refuses a guest.
    func registerDeviceToken(_ token: String, userID: UUID, environment: String) async throws {
        struct Upsert: Encodable {
            let token: String
            let userId: UUID
            let environment: String
            enum CodingKeys: String, CodingKey { case token, environment, userId = "user_id" }
        }
        try await client
            .from("device_tokens")
            .upsert(Upsert(token: token, userId: userID, environment: environment), onConflict: "token")
            .execute()
    }

    /// Forgets this device — on sign-out, so the next member's likes don't
    /// buzz the previous one's phone. RLS limits it to the caller's own row.
    func removeDeviceToken(_ token: String) async throws {
        try await client
            .from("device_tokens")
            .delete()
            .eq("token", value: token)
            .execute()
    }
}

// MARK: - Community DTOs

/// Read model for the `community_members` view and `search_members()`.
/// Not private: a guide's follower faces (`InstructorSocialRow`, in
/// +Catalog) decode as this too.
struct CommunityMemberRow: Decodable {
    let id: UUID
    let displayName: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl   = "avatar_url"
    }

    var member: CommunityMember {
        CommunityMember(id: id, displayName: displayName, avatarUrl: avatarUrl)
    }
}

/// Read model for one row of `practice_presence()`.
private struct PracticePresenceRow: Decodable {
    let contentKind: String
    let contentId: Int
    let present: Int
    let faces: [CommunityMemberRow]

    enum CodingKeys: String, CodingKey {
        case present, faces
        case contentKind = "content_kind"
        case contentId   = "content_id"
    }

    var presence: Presence { Presence(count: present, faces: faces.map(\.member)) }
}

/// Read model for one row of `program_presence()`.
private struct ProgramPresenceRow: Decodable {
    let programId: String
    let present: Int
    let faces: [CommunityMemberRow]

    enum CodingKeys: String, CodingKey {
        case present, faces
        case programId = "program_id"
    }

    var presence: Presence { Presence(count: present, faces: faces.map(\.member)) }
}

/// Read model for the `community_activity` view.
private struct CommunityActivityRow: Decodable {
    let playId: UUID
    let userId: UUID
    let displayName: String
    let avatarUrl: String?
    let contentKind: String
    let contentId: Int
    let contentTitle: String
    let category: String?
    let completedAt: Date
    /// Optional so a feed row from before 0016 still decodes.
    let likeCount: Int?
    let likedByMe: Bool?

    enum CodingKeys: String, CodingKey {
        case category
        case playId       = "play_id"
        case userId       = "user_id"
        case displayName  = "display_name"
        case avatarUrl    = "avatar_url"
        case contentKind  = "content_kind"
        case contentId    = "content_id"
        case contentTitle = "content_title"
        case completedAt  = "completed_at"
        case likeCount    = "like_count"
        case likedByMe    = "liked_by_me"
    }

    /// Nil for a kind this build doesn't know — a line that can't say what was
    /// practiced is better left out than mislabelled.
    var activity: CommunityActivity? {
        guard let kind = PracticeContentKind(rawValue: contentKind) else { return nil }
        return CommunityActivity(
            id: playId,
            member: CommunityMember(id: userId, displayName: displayName, avatarUrl: avatarUrl),
            kind: kind,
            contentID: contentId,
            title: contentTitle,
            category: category.flatMap(PracticeCategory.init(rawValue:)),
            completedAt: completedAt,
            likeCount: likeCount ?? 0,
            likedByMe: likedByMe ?? false
        )
    }
}

/// Read model for the `member_notifications` view.
private struct NotificationRow: Decodable {
    let id: UUID
    let actorId: UUID?
    let actorName: String?
    let actorAvatarUrl: String?
    let playId: UUID?
    let contentTitle: String?
    let createdAt: Date
    let readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case actorId        = "actor_id"
        case actorName      = "actor_name"
        case actorAvatarUrl = "actor_avatar_url"
        case playId         = "play_id"
        case contentTitle   = "content_title"
        case createdAt      = "created_at"
        case readAt         = "read_at"
    }

    var notification: LikeNotification {
        LikeNotification(
            id: id,
            actor: actorId.map { CommunityMember(id: $0, displayName: actorName ?? "A member",
                                                 avatarUrl: actorAvatarUrl) },
            playID: playId,
            practiceTitle: contentTitle,
            createdAt: createdAt,
            readAt: readAt
        )
    }
}

private struct FriendshipRow: Decodable {
    let requesterId: UUID
    let addresseeId: UUID
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case createdAt   = "created_at"
    }
}
