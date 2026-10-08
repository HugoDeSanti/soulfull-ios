//
//  BlockedMembersViewModel.swift
//  Soulfull Gatherings
//
//  The You tab's list of members this member has blocked, and Unblock. The
//  blocked are out of every Community read for the blocker (0028), so they
//  come from `blocked_members()`, which answers only the caller's own blocks.
//
//  Unblocking brings them back into each other's Community. It doesn't bring
//  back what the block ended: a friendship, a pending request, likes.
//

import SwiftUI

@Observable @MainActor
final class BlockedMembersViewModel {

    private(set) var members: [CommunityMember] = []
    /// The list has answered at least once — "No one blocked" only counts then.
    private(set) var hasLoaded = false
    private(set) var failure: CommunityLoadFailure?
    private(set) var actionError: String?
    private(set) var busy: Set<UUID> = []

    private let fetch: @MainActor () async throws -> [CommunityMember]
    private let unblockMember: @MainActor (UUID) async throws -> Void

    init(fetch: (@MainActor () async throws -> [CommunityMember])? = nil,
         unblock: (@MainActor (UUID) async throws -> Void)? = nil) {
        self.fetch = fetch ?? Self.liveFetch
        self.unblockMember = unblock ?? Self.liveUnblock
    }

    func load() async {
        do {
            let rows = try await fetch()
            members = rows
            failure = nil
            hasLoaded = true
        } catch where error.isCancellation {
            return
        } catch {
            Log.data.info("Blocked members unavailable: \(error.localizedDescription)")
            failure = CommunityLoadFailure(offline: error.isOffline)
        }
    }

    /// Off the list at once; back on it if the server refuses.
    func unblock(_ member: CommunityMember) async {
        guard !busy.contains(member.id), let index = members.firstIndex(of: member) else { return }
        busy.insert(member.id)
        defer { busy.remove(member.id) }
        actionError = nil
        members.remove(at: index)
        do {
            try await unblockMember(member.id)
            Haptics.success()
        } catch {
            Haptics.bump()
            Log.data.error("Unblock failed: \(error.localizedDescription)")
            members.insert(member, at: min(index, members.count))
            actionError = error.isOffline
                ? "You're offline, so \(member.displayName) is still blocked. Reconnect and try again."
                : "We couldn't unblock \(member.displayName) just now. Please try again."
        }
    }

    // MARK: - Live

    private static func liveFetch() async throws -> [CommunityMember] {
        #if DEBUG
        if isPreview { return previewBlocked }
        #endif
        return try await SupabaseService.shared.fetchBlockedMembers()
    }

    private static func liveUnblock(_ memberID: UUID) async throws {
        #if DEBUG
        if isPreview { return }
        #endif
        guard let userID = SupabaseService.shared.client.auth.currentUser?.id else { throw AppError.unknown }
        try await SupabaseService.shared.unblockMember(memberID, userID: userID)
    }

    #if DEBUG
    /// `-preview-you` (the You tab's fixture) lists one blocked member, so the
    /// list and Unblock can be seen and tested without two accounts.
    private static var isPreview: Bool { ProfileViewModel.isPreview }
    private static let previewBlocked = [
        CommunityMember(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000b1")!,
                        displayName: "Sam K.", avatarUrl: nil),
    ]
    #endif
}
