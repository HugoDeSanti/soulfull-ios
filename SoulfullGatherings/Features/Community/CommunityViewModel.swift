//
//  CommunityViewModel.swift
//  Soulfull Gatherings
//
//  The Community tab's state: the feed (everyone, or just friends), this
//  member's friendships, and the search that finds someone to add.
//
//  Nothing here is invented and nothing is written locally — the feed is the
//  `community_activity` view over the same ledger the You tab counts, and a
//  friendship is a row on `friendships`. A guest can read the feed (browsing
//  is open); the Friends filter and everything on the Friends screen need an
//  account, and the server refuses a guest even if the gate didn't.
//

import SwiftUI

/// Whose practice the feed shows.
enum CommunityScope: String, CaseIterable, Identifiable, Hashable {
    case all, friends
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:     "All"
        case .friends: "Friends"
        }
    }
}

/// Why the feed has nothing to show, when it isn't because there is nothing.
enum CommunityLoadFailure: Equatable {
    case offline
    case failed

    init(offline: Bool) { self = offline ? .offline : .failed }

    var title: String {
        switch self {
        case .offline: "No internet connection"
        case .failed:  "Couldn't load the community"
        }
    }

    var detail: String {
        switch self {
        case .offline: "You'll need to be online to see what everyone's practising. Reconnect and try again."
        case .failed:  "Something went wrong at our end. Please try again in a moment."
        }
    }
}

@Observable @MainActor
final class CommunityViewModel {

    var scope: CommunityScope = .all

    /// Everyone's finished practices, newest first.
    private(set) var allActivity: [CommunityActivity] = []
    /// Friends' only — fetched server-side by their ids, not filtered from
    /// `allActivity`, because a friend's last practice can be older than the
    /// last hundred lines of everyone's.
    private(set) var friendsActivity: [CommunityActivity] = []
    private(set) var friendships: [Friendship] = []

    private(set) var isLoadingActivity = false
    private(set) var activityFailure: CommunityLoadFailure?
    private(set) var friendshipsFailure: CommunityLoadFailure?
    private(set) var activityLoaded: Set<CommunityScope> = []
    private(set) var friendshipsLoaded = false

    // Search
    var searchQuery = "" { didSet { if searchQuery != oldValue { scheduleSearch() } } }
    private(set) var searchResults: [CommunityMember] = []
    private(set) var isSearching = false
    private var searchTask: Task<Void, Never>?

    /// A friend action that failed, for a banner. Cleared on the next action.
    private(set) var actionError: String?
    /// Ids with an action in flight, so a button can't double-fire.
    private(set) var busy: Set<UUID> = []

    private var loadedFor: UUID?

    var userID: UUID? { SupabaseService.shared.client.auth.currentUser?.id }

    /// Whose lines read "You" in the feed.
    var selfID: UUID? {
        #if DEBUG
        if Self.isPreview { return Self.previewSelf }
        #endif
        return userID
    }

    /// `-preview-community`: renders the tab against fixtures, so the populated
    /// screen can be worked on (and tested) without accounts or a seeded
    /// backend. Always false in Release.
    static var isPreview: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-preview-community")
        #else
        false
        #endif
    }

    // MARK: - Reading

    var activity: [CommunityActivity] {
        scope == .all ? allActivity : friendsActivity
    }

    var friends: [Friendship] { friendships.filter(\.isAccepted) }
    var incomingRequests: [Friendship] { friendships.filter { !$0.isAccepted && $0.direction == .received } }
    var outgoingRequests: [Friendship] { friendships.filter { !$0.isAccepted && $0.direction == .sent } }
    var friendIDs: [UUID] { friends.map(\.otherID) }

    func standing(for memberID: UUID) -> FriendStanding {
        guard let row = friendships.first(where: { $0.otherID == memberID }) else { return .none }
        if row.isAccepted { return .friends }
        return row.direction == .sent ? .requested : .awaitingMyAnswer
    }

    // MARK: - Loading

    /// Cheap on appear — no-ops for a scope already in hand. `force` is pull to
    /// refresh. `isMember` false skips the friendship read (the server would
    /// only answer a guest with an empty list anyway).
    func load(isMember: Bool, force: Bool = false) async {
        #if DEBUG
        if Self.isPreview { installPreviewFixture(); return }
        #endif
        if loadedFor != userID { reset() }
        loadedFor = userID
        if isMember {
            await loadFriendships(force: force)
        }
        await loadActivity(force: force)
    }

    func loadActivity(force: Bool = false) async {
        let scope = self.scope
        #if DEBUG
        if Self.isPreview {
            let ids = Set(friendIDs)
            friendsActivity = allActivity.filter { ids.contains($0.member.id) }
            activityLoaded.insert(scope)
            return
        }
        #endif
        guard force || !activityLoaded.contains(scope) || activityFailure != nil else { return }
        isLoadingActivity = true
        defer { isLoadingActivity = false }
        do {
            let rows: [CommunityActivity]
            switch scope {
            case .all:     rows = try await SupabaseService.shared.fetchCommunityActivity()
            case .friends: rows = try await SupabaseService.shared.fetchCommunityActivity(memberIDs: friendIDs)
            }
            switch scope {
            case .all:     allActivity = rows
            case .friends: friendsActivity = rows
            }
            activityFailure = nil
            activityLoaded.insert(scope)
        } catch where error.isCancellation {
            return
        } catch {
            Log.data.info("Community feed unavailable: \(error.localizedDescription)")
            activityFailure = CommunityLoadFailure(offline: error.isOffline)
        }
    }

    func loadFriendships(force: Bool = false) async {
        guard let userID else { return }
        guard force || !friendshipsLoaded || friendshipsFailure != nil else { return }
        do {
            friendships = try await SupabaseService.shared.fetchFriendships(userID: userID)
            friendshipsFailure = nil
            friendshipsLoaded = true
            // The friends feed is keyed by who the friends are.
            activityLoaded.remove(.friends)
        } catch where error.isCancellation {
            return
        } catch {
            Log.data.info("Friendships unavailable: \(error.localizedDescription)")
            friendshipsFailure = CommunityLoadFailure(offline: error.isOffline)
        }
    }

    private func reset() {
        allActivity = []
        friendsActivity = []
        friendships = []
        activityFailure = nil
        friendshipsFailure = nil
        activityLoaded = []
        friendshipsLoaded = false
        searchResults = []
    }

    // MARK: - Friends

    func sendRequest(to member: CommunityMember) async {
        guard let userID else { return }
        await perform(on: member.id) {
            try await SupabaseService.shared.sendFriendRequest(from: userID, to: member.id)
        } optimistic: {
            friendships.insert(Friendship(requesterID: userID, addresseeID: member.id, status: .pending,
                                          createdAt: .now, other: member, direction: .sent), at: 0)
        }
    }

    func accept(_ friendship: Friendship) async {
        guard let userID, friendship.direction == .received else { return }
        await perform(on: friendship.otherID) {
            try await SupabaseService.shared.acceptFriendRequest(from: friendship.requesterID, userID: userID)
        } optimistic: {
            friendships = friendships.map { row in
                guard row.id == friendship.id else { return row }
                return Friendship(requesterID: row.requesterID, addresseeID: row.addresseeID, status: .accepted,
                                  createdAt: row.createdAt, other: row.other, direction: row.direction)
            }
        }
    }

    /// Decline, withdraw, or unfriend.
    func remove(_ friendship: Friendship) async {
        guard let userID else { return }
        await perform(on: friendship.otherID) {
            try await SupabaseService.shared.removeFriendship(between: userID, and: friendship.otherID)
        } optimistic: {
            friendships.removeAll { $0.id == friendship.id }
        }
    }

    /// Applies the change locally first so the button answers at once, then
    /// asks the server; on failure the truth is re-read rather than guessed.
    private func perform(on memberID: UUID, _ action: () async throws -> Void,
                         optimistic: () -> Void) async {
        guard !busy.contains(memberID) else { return }
        busy.insert(memberID)
        defer { busy.remove(memberID) }
        actionError = nil
        let before = friendships
        optimistic()
        #if DEBUG
        if Self.isPreview { Haptics.success(); activityLoaded.remove(.friends); return }
        #endif
        do {
            try await action()
            Haptics.success()
            await loadFriendships(force: true)
        } catch {
            Haptics.bump()
            Log.data.error("Friend action failed: \(error.localizedDescription)")
            friendships = before
            actionError = error.isOffline
                ? "You're offline. Reconnect and try again."
                : "That didn't go through. Please try again."
        }
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { searchResults = []; isSearching = false; return }
        isSearching = true
        searchTask = Task { [weak self] in
            // Debounced: one request per pause in typing, not per keystroke.
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled, let self else { return }
            await self.search(query)
        }
    }

    private func search(_ query: String) async {
        #if DEBUG
        if Self.isPreview {
            searchResults = Self.previewDirectory.filter {
                $0.displayName.localizedCaseInsensitiveContains(query)
            }
            isSearching = false
            return
        }
        #endif
        do {
            let results = try await SupabaseService.shared.searchMembers(query)
            guard !Task.isCancelled, searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            searchResults = results
        } catch where error.isCancellation {
            return
        } catch {
            Log.data.info("Member search failed: \(error.localizedDescription)")
            searchResults = []
        }
        isSearching = false
    }

    // MARK: - Preview fixture

    #if DEBUG
    /// Four members, one of them "you". Six finished practices spread over
    /// today, yesterday and last week — the three day groups the feed draws —
    /// two friends, one request waiting on you, one you've sent. What
    /// `CommunityTests` asserts on.
    static let previewSelf = UUID(uuidString: "00000000-0000-0000-0000-00000000aaaa")!
    private static let alma  = CommunityMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Alma G.", avatarUrl: nil)
    private static let theo  = CommunityMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, displayName: "Theo R.", avatarUrl: nil)
    private static let nia   = CommunityMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, displayName: "Nia", avatarUrl: nil)
    private static let mateo = CommunityMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, displayName: "Mateo V.", avatarUrl: nil)
    private static let me    = CommunityMember(id: previewSelf, displayName: "Hugo D.", avatarUrl: nil)
    static let previewDirectory = [alma, theo, nia, mateo]

    private func installPreviewFixture() {
        // Once. A request accepted on the Friends screen must survive the next
        // appear of the tab, or the test can't watch it move.
        guard !friendshipsLoaded else { return }
        func ago(_ hours: Double) -> Date { Date.now.addingTimeInterval(-hours * 3600) }
        func line(_ m: CommunityMember, _ kind: PracticeContentKind, _ id: Int, _ title: String,
                  _ category: PracticeCategory?, _ hours: Double) -> CommunityActivity {
            CommunityActivity(id: UUID(), member: m, kind: kind, contentID: id, title: title,
                              category: category, completedAt: ago(hours))
        }
        allActivity = [
            line(Self.alma,  .session,  11, "Confidence Boost",     .breathwork, 0.2),
            line(Self.me,    .exercise, 2,  "Morning Mobility",     nil,         1.5),
            line(Self.theo,  .session,  12, "Body Scan for Sleep",  .meditation, 5),
            line(Self.nia,   .recipe,   1,  "Golden Turmeric Broth", nil,        27),
            line(Self.mateo, .session,  13, "Shaking It Out",       .somatic,    30),
            line(Self.alma,  .exercise, 3,  "Core & Ground",        nil,         26 * 6),
        ]
        friendships = [
            Friendship(requesterID: Self.previewSelf, addresseeID: Self.alma.id, status: .accepted,
                       createdAt: ago(200), other: Self.alma, direction: .sent),
            Friendship(requesterID: Self.theo.id, addresseeID: Self.previewSelf, status: .accepted,
                       createdAt: ago(300), other: Self.theo, direction: .received),
            Friendship(requesterID: Self.nia.id, addresseeID: Self.previewSelf, status: .pending,
                       createdAt: ago(3), other: Self.nia, direction: .received),
            Friendship(requesterID: Self.previewSelf, addresseeID: Self.mateo.id, status: .pending,
                       createdAt: ago(50), other: Self.mateo, direction: .sent),
        ]
        let ids = Set(friendIDs)
        friendsActivity = allActivity.filter { ids.contains($0.member.id) }
        activityLoaded = [.all, .friends]
        friendshipsLoaded = true
        activityFailure = nil
        friendshipsFailure = nil
    }
    #endif
}
