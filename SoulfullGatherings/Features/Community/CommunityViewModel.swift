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
        case .offline: "You'll need to be online to see what everyone's practicing. Reconnect and try again."
        case .failed:  "Something went wrong at our end. Please try again in a moment."
        }
    }
}

/// The reads the Community tab makes, and the clock it judges their age by.
///
/// Injectable so the loading rules — how long a read stays fresh, the Friends
/// feed waiting for the friends, the reset between members, marking only what
/// was shown — can be tested without a network
/// (`SoulfullTests/Community/CommunityLoadTests`). The app always uses `.live`.
/// Accepting, removing and likes are writes with their own optimistic handling
/// and still go straight to `SupabaseService`; sending a request, blocking and
/// reporting come through here, because what they do on failure is a rule
/// (`CommunitySafetyTests`).
struct CommunityBackend {
    var currentUserID: @MainActor () -> UUID?
    /// Everyone's feed for nil; only these members' otherwise.
    var fetchActivity: @MainActor (_ memberIDs: [UUID]?) async throws -> [CommunityActivity]
    var fetchFriendships: @MainActor (_ userID: UUID) async throws -> [Friendship]
    var fetchNotifications: @MainActor (_ userID: UUID) async throws -> [LikeNotification]
    /// Stamps exactly these notifications read — never "everything unread".
    var markNotificationsRead: @MainActor (_ userID: UUID, _ ids: [UUID]) async throws -> Void
    var searchMembers: @MainActor (_ query: String) async throws -> [CommunityMember]
    var sendFriendRequest: @MainActor (_ from: UUID, _ to: UUID) async throws -> Void
    /// Blocks `memberID` on behalf of `userID` (0028).
    var block: @MainActor (_ memberID: UUID, _ userID: UUID) async throws -> Void
    var report: @MainActor (_ report: MemberReport) async throws -> Void
    var now: @MainActor () -> Date

    /// Computed rather than stored, so there is no shared global to make
    /// `Sendable`.
    static var live: CommunityBackend {
        CommunityBackend(
            currentUserID: { SupabaseService.shared.client.auth.currentUser?.id },
            fetchActivity: { try await SupabaseService.shared.fetchCommunityActivity(memberIDs: $0) },
            fetchFriendships: { try await SupabaseService.shared.fetchFriendships(userID: $0) },
            fetchNotifications: { try await SupabaseService.shared.fetchNotifications(userID: $0) },
            markNotificationsRead: { try await SupabaseService.shared.markNotificationsRead(userID: $0, ids: $1) },
            searchMembers: { try await SupabaseService.shared.searchMembers($0) },
            sendFriendRequest: { try await SupabaseService.shared.sendFriendRequest(from: $0, to: $1) },
            block: { try await SupabaseService.shared.blockMember($0, userID: $1) },
            report: { try await SupabaseService.shared.reportMember($0) },
            now: { Date.now }
        )
    }
}

@Observable @MainActor
final class CommunityViewModel: MemberSafetyActions {

    /// How long a read stays current. Coming back to the tab inside it shows
    /// what is already there; after it, the tab reads again — quietly, over the
    /// lines on screen, never a spinner over content — the same minute
    /// `PresenceStore` allows its counts. The tab's view model lives for the
    /// whole session, so without this the feed, the friends and the bell were
    /// read on the first visit and never again.
    static let freshFor: TimeInterval = 60

    var scope: CommunityScope = .all

    /// Everyone's finished practices, newest first.
    private(set) var allActivity: [CommunityActivity] = []
    /// Friends' only — fetched server-side by their ids, not filtered from
    /// `allActivity`, because a friend's last practice can be older than the
    /// last hundred lines of everyone's.
    private(set) var friendsActivity: [CommunityActivity] = []
    private(set) var friendships: [Friendship] = []
    /// Likes on this member's practices, newest first.
    private(set) var notifications: [LikeNotification] = []
    private(set) var notificationsLoaded = false
    private(set) var notificationsFailure: CommunityLoadFailure?

    private(set) var activityFailure: CommunityLoadFailure?
    private(set) var friendshipsFailure: CommunityLoadFailure?
    private(set) var friendshipsLoaded = false

    /// When each feed last answered. Absent means never, for this member.
    private var activityLoadedAt: [CommunityScope: Date] = [:]
    /// Who the friends were when the Friends feed was read. That feed is read
    /// by their ids, so a different set — a request accepted, a friend removed
    /// — makes it out of date however recent the read was.
    private var friendsFeedReadFor: Set<UUID>?
    private var friendshipsLoadedAt: Date?
    private var notificationsLoadedAt: Date?
    /// Feeds with a read in flight. Two tasks ask on every appear (the
    /// identity load and the scope load), and only one of them should fetch.
    private var activityInFlight: Set<CommunityScope> = []
    /// Bumped by `reset()`. A read that started for the previous member checks
    /// it before landing, so their lines never arrive on the next one's screen.
    @ObservationIgnored private var generation = 0

    var activityLoaded: Set<CommunityScope> { Set(activityLoadedAt.keys) }
    var isLoadingActivity: Bool { activityInFlight.contains(scope) }

    // Search
    var searchQuery = "" { didSet { if searchQuery != oldValue { scheduleSearch() } } }
    private(set) var searchResults: [CommunityMember] = []
    private(set) var isSearching = false
    /// Why the last search came back empty, when it isn't that nobody matched.
    private(set) var searchFailure: CommunityLoadFailure?
    private var searchTask: Task<Void, Never>?

    /// A friend action that failed, for a banner. Cleared on the next action.
    private(set) var actionError: String?
    /// Ids with an action in flight, so a button can't double-fire.
    private(set) var busy: Set<UUID> = []

    /// Members blocked from this screen this session. The server already
    /// leaves them out of every read once the block lands (0028); this keeps
    /// them off screen meanwhile — including from a read that set off before
    /// the block and answers after it.
    private(set) var hiddenMembers: Set<UUID> = []

    private var loadedFor: UUID?
    private let backend: CommunityBackend

    init(backend: CommunityBackend = .live) {
        self.backend = backend
    }

    var userID: UUID? { backend.currentUserID() }

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
    var unreadCount: Int { notifications.filter(\.isUnread).count }

    /// The showing feed hasn't answered yet — including the frame before its
    /// read has started, and the Friends feed while the friends themselves are
    /// still on their way (it is read by their ids, so it can't start sooner).
    var isAwaitingFeed: Bool {
        if scope == .friends, !friendshipsLoaded { return friendshipsFailure == nil }
        return isLoadingActivity || (activityFailure == nil && !activityLoaded.contains(scope))
    }

    /// Why the showing feed has nothing to show, when it isn't that there is
    /// nothing. Without the friends there is no Friends feed to read, so a
    /// failed friends read is its failure too — rather than an invitation to
    /// add friends to someone who already has them.
    var feedFailure: CommunityLoadFailure? {
        if scope == .friends, !friendshipsLoaded, let friendshipsFailure { return friendshipsFailure }
        return activityFailure
    }

    func standing(for memberID: UUID) -> FriendStanding {
        guard let row = friendships.first(where: { $0.otherID == memberID }) else { return .none }
        if row.isAccepted { return .friends }
        return row.direction == .sent ? .requested : .awaitingMyAnswer
    }

    // MARK: - Loading

    /// Cheap on appear — reads only what is missing, failed, or older than
    /// `freshFor`, so re-selecting the tab after a while brings it up to date
    /// without a spinner. `force` is pull to refresh. `isMember` false skips the
    /// friendship and notification reads (the server would only answer a guest
    /// with empty lists anyway).
    func load(isMember: Bool, force: Bool = false) async {
        #if DEBUG
        if Self.isPreview { installPreviewFixture(); return }
        #endif
        if loadedFor != userID {
            // Nothing to clear before the first load — and clearing would throw
            // away the scope task's read of this same person's feed, already
            // in flight on the same appear.
            if loadedFor != nil { reset() }
            loadedFor = userID
        }
        if isMember {
            async let friends: Void = loadFriendships(force: force)
            async let bell: Void = loadNotifications(force: force)
            _ = await (friends, bell)
        }
        // After the friends: the Friends feed is read by their ids, and waits
        // for them (see `loadActivity`).
        await loadActivity(force: force)
    }

    /// `force` is for when something new is known to be waiting — the
    /// Notifications screen opening, a tapped like push.
    func loadNotifications(force: Bool = false) async {
        #if DEBUG
        if Self.isPreview { return }
        #endif
        guard let userID else { return }
        guard force || notificationsFailure != nil || !isFresh(notificationsLoadedAt) else { return }
        let generation = self.generation
        do {
            let rows = try await backend.fetchNotifications(userID)
            guard generation == self.generation else { return }
            notifications = rows.filter { !isHidden($0.actor?.id) }
            notificationsFailure = nil
            notificationsLoaded = true
            notificationsLoadedAt = backend.now()
        } catch where error.isCancellation {
            return
        } catch {
            guard generation == self.generation else { return }
            Log.data.info("Notifications unavailable: \(error.localizedDescription)")
            notificationsFailure = CommunityLoadFailure(offline: error.isOffline)
        }
    }

    /// Marks read the notifications the Notifications screen has shown. By id,
    /// not "everything unread on the server": that also stamped a like which
    /// arrived after the list was read, so it was marked read without ever
    /// being seen. Optimistic; the server latches `read_at` anyway.
    func markRead(_ ids: Set<UUID>) async {
        let marking = Set(notifications.filter { $0.isUnread && ids.contains($0.id) }.map(\.id))
        guard !marking.isEmpty else { return }
        let now = backend.now()
        notifications = notifications.map { note in
            guard marking.contains(note.id) else { return note }
            return LikeNotification(id: note.id, actor: note.actor, playID: note.playID,
                                    practiceTitle: note.practiceTitle, createdAt: note.createdAt,
                                    readAt: now)
        }
        #if DEBUG
        if Self.isPreview { return }
        #endif
        guard let userID else { return }
        do {
            try await backend.markNotificationsRead(userID, Array(marking))
        } catch {
            Log.data.info("Mark-read failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Likes

    /// Likes or unlikes one line. Both feeds update at once so the count
    /// agrees whichever scope is showing; the server's answer wins on failure.
    func toggleLike(_ line: CommunityActivity) async {
        guard let userID, line.member.id != selfID, !busy.contains(line.id) else { return }
        busy.insert(line.id)
        defer { busy.remove(line.id) }
        let liking = !line.likedByMe
        apply(to: line.id) { $0.likedByMe = liking; $0.likeCount = max(0, $0.likeCount + (liking ? 1 : -1)) }
        liking ? Haptics.bump() : Haptics.tap()
        #if DEBUG
        if Self.isPreview { return }
        #endif
        do {
            if liking {
                try await SupabaseService.shared.likeActivity(playID: line.id, userID: userID)
            } else {
                try await SupabaseService.shared.unlikeActivity(playID: line.id, userID: userID)
            }
        } catch where error.isCancellation {
            return
        } catch {
            Log.data.info("Like failed: \(error.localizedDescription)")
            apply(to: line.id) { $0.likedByMe = !liking; $0.likeCount = max(0, $0.likeCount + (liking ? -1 : 1)) }
            Haptics.bump()
        }
    }

    private func apply(to playID: UUID, _ change: (inout CommunityActivity) -> Void) {
        for i in allActivity.indices where allActivity[i].id == playID { change(&allActivity[i]) }
        for i in friendsActivity.indices where friendsActivity[i].id == playID { change(&friendsActivity[i]) }
    }

    func loadActivity(force: Bool = false) async {
        let scope = self.scope
        #if DEBUG
        if Self.isPreview {
            let ids = Set(friendIDs)
            friendsActivity = allActivity.filter { ids.contains($0.member.id) }
            activityLoadedAt[scope] = .now
            return
        }
        #endif
        // The Friends feed is read by who the friends are, so it waits for
        // them. Read before they had arrived it was an empty list marked as
        // loaded — "Practice alongside people you know" to someone with
        // friends, straight after signing in from the Friends gate. `load()`
        // reads it once they're in; until then the screen says it's loading,
        // or why the friends couldn't be read.
        if scope == .friends, !friendshipsLoaded { return }
        guard !activityInFlight.contains(scope) else { return }
        guard force || activityFailure != nil || !isCurrent(scope) else { return }
        let generation = self.generation
        let ids = friendIDs
        activityInFlight.insert(scope)
        defer { if generation == self.generation { activityInFlight.remove(scope) } }
        do {
            let rows = try await backend.fetchActivity(scope == .all ? nil : ids)
            guard generation == self.generation else { return }
            let shown = rows.filter { !isHidden($0.member.id) }
            switch scope {
            case .all:
                allActivity = shown
            case .friends:
                friendsActivity = shown
                friendsFeedReadFor = Set(ids)
            }
            activityFailure = nil
            activityLoadedAt[scope] = backend.now()
        } catch where error.isCancellation {
            return
        } catch {
            guard generation == self.generation else { return }
            Log.data.info("Community feed unavailable: \(error.localizedDescription)")
            activityFailure = CommunityLoadFailure(offline: error.isOffline)
        }
    }

    func loadFriendships(force: Bool = false) async {
        #if DEBUG
        // The fixture's friendships stand; a read would replace them with the
        // preview session's own (none), as the Friends screen asks on appear.
        if Self.isPreview { return }
        #endif
        guard let userID else { return }
        guard force || friendshipsFailure != nil || !isFresh(friendshipsLoadedAt) else { return }
        let generation = self.generation
        do {
            let rows = try await backend.fetchFriendships(userID)
            guard generation == self.generation else { return }
            friendships = rows.filter { !isHidden($0.otherID) }
            friendshipsFailure = nil
            friendshipsLoaded = true
            friendshipsLoadedAt = backend.now()
        } catch where error.isCancellation {
            return
        } catch {
            guard generation == self.generation else { return }
            Log.data.info("Friendships unavailable: \(error.localizedDescription)")
            friendshipsFailure = CommunityLoadFailure(offline: error.isOffline)
        }
    }

    private func isHidden(_ memberID: UUID?) -> Bool {
        guard let memberID else { return false }
        return hiddenMembers.contains(memberID)
    }

    private func isFresh(_ loadedAt: Date?) -> Bool {
        guard let loadedAt else { return false }
        return backend.now().timeIntervalSince(loadedAt) < Self.freshFor
    }

    /// A feed is current while it's fresh — and, for the Friends feed, while
    /// the friends are still the ones it was read for.
    private func isCurrent(_ scope: CommunityScope) -> Bool {
        guard isFresh(activityLoadedAt[scope]) else { return false }
        return scope == .all || friendsFeedReadFor == Set(friendIDs)
    }

    /// Everything that belonged to whoever was here before — their feed,
    /// friends and likes, and what they left on screen: the Friends filter, a
    /// half-typed search, a failed action's banner. Leaving those behind showed
    /// a guest the Friends filter with "Find friends" after a sign-out, and the
    /// next member the last one's search. Runs when the person behind the
    /// session changes.
    private func reset() {
        generation += 1
        scope = .all
        allActivity = []
        friendsActivity = []
        friendships = []
        notifications = []
        notificationsLoaded = false
        notificationsFailure = nil
        activityFailure = nil
        friendshipsFailure = nil
        friendshipsLoaded = false
        activityLoadedAt = [:]
        friendsFeedReadFor = nil
        friendshipsLoadedAt = nil
        notificationsLoadedAt = nil
        activityInFlight = []
        searchTask?.cancel()
        searchQuery = ""
        searchResults = []
        isSearching = false
        searchFailure = nil
        actionError = nil
        busy = []
        hiddenMembers = []
    }

    // MARK: - Friends

    func sendRequest(to member: CommunityMember) async {
        guard let userID else { return }
        await perform(on: member.id, member: member) {
            try await self.backend.sendFriendRequest(userID, member.id)
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
    /// `member` names them in a refusal that's about them (the cooldown).
    private func perform(on memberID: UUID, member: CommunityMember? = nil,
                         _ action: () async throws -> Void,
                         optimistic: () -> Void) async {
        guard !busy.contains(memberID) else { return }
        busy.insert(memberID)
        defer { busy.remove(memberID) }
        actionError = nil
        let before = friendships
        optimistic()
        #if DEBUG
        if Self.isPreview { Haptics.success(); activityLoadedAt[.friends] = nil; return }
        #endif
        do {
            try await action()
            Haptics.success()
            await loadFriendships(force: true)
        } catch {
            Haptics.bump()
            Log.data.error("Friend action failed: \(error.localizedDescription)")
            friendships = before
            actionError = Self.friendActionMessage(for: error, about: member)
        }
    }

    /// What a failed friend action says. A request inside the 30 days after
    /// the last one to that person was declined (0028) is refused by the
    /// server with `friend_request_cooldown`, and says so rather than "try
    /// again" — trying again is exactly what won't work.
    static func friendActionMessage(for error: any Error, about member: CommunityMember?) -> String {
        if error.isOffline { return "You're offline. Reconnect and try again." }
        if error.isFriendRequestCooldown {
            let name = member?.displayName ?? "them"
            return "You can send \(name) another request 30 days after your last one was declined."
        }
        return "That didn't go through. Please try again."
    }

    // MARK: - Safety

    /// Blocks a member (0028): from now on neither sees the other anywhere in
    /// Community, any friendship or request between them ends, and their likes
    /// on each other's practices go. They aren't told. Off screen at once;
    /// back on screen only if the server refuses. Returns whether it held.
    @discardableResult
    func block(_ member: CommunityMember) async -> Bool {
        guard let userID, member.id != selfID, !busy.contains(member.id) else { return false }
        busy.insert(member.id)
        defer { busy.remove(member.id) }
        actionError = nil
        let before = (all: allActivity, friends: friendsActivity, friendships: friendships,
                      notifications: notifications, search: searchResults)
        hiddenMembers.insert(member.id)
        allActivity.removeAll { $0.member.id == member.id }
        friendsActivity.removeAll { $0.member.id == member.id }
        friendships.removeAll { $0.otherID == member.id }
        notifications.removeAll { $0.actor?.id == member.id }
        searchResults.removeAll { $0.id == member.id }
        #if DEBUG
        if Self.isPreview { Haptics.success(); return true }
        #endif
        do {
            try await backend.block(member.id, userID)
            Haptics.success()
            // Their likes on my lines went with the block; the counts follow.
            activityLoadedAt = [:]
            await loadActivity(force: true)
            return true
        } catch {
            Haptics.bump()
            Log.data.error("Block failed: \(error.localizedDescription)")
            hiddenMembers.remove(member.id)
            allActivity = before.all
            friendsActivity = before.friends
            friendships = before.friendships
            notifications = before.notifications
            searchResults = before.search
            actionError = error.isOffline
                ? "You're offline, so \(member.displayName) isn't blocked. Reconnect and try again."
                : "We couldn't block \(member.displayName) just now. Please try again."
            return false
        }
    }

    /// Files a report with the team. Throws so the sheet can offer a retry and
    /// keep what was written; the sheet owns its sending state.
    func report(_ report: MemberReport) async throws {
        #if DEBUG
        if Self.isPreview { try await Task.sleep(for: .milliseconds(400)); return }
        #endif
        try await backend.report(report)
    }

    // MARK: - Search

    /// The same query again, after a failed search.
    func retrySearch() {
        scheduleSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            searchFailure = nil
            return
        }
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
            let results = try await backend.searchMembers(query)
            guard !Task.isCancelled, isCurrentSearch(query) else { return }
            searchResults = results.filter { !isHidden($0.id) }
            searchFailure = nil
        } catch where error.isCancellation {
            return
        } catch {
            guard isCurrentSearch(query) else { return }
            Log.data.info("Member search failed: \(error.localizedDescription)")
            // Said as a failure, not as "No one by that name yet" — that
            // sentence is about the directory, and the directory never
            // answered.
            searchResults = []
            searchFailure = CommunityLoadFailure(offline: error.isOffline)
        }
        isSearching = false
    }

    /// Still what's in the field — a slower answer to an earlier query must not
    /// land over a newer one.
    private func isCurrentSearch(_ query: String) -> Bool {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query
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
        let calendar = Calendar.current
        let now = Date.now
        let startOfToday = calendar.startOfDay(for: now)
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        // The feed groups by day, and the tests read its headings, so each
        // line is pinned to the day it stands for. Plain "hours ago" put the
        // whole of "today" on yesterday between midnight and 5am, and failed
        // CommunityTests and MemberSafetyTests on any run in the small hours.
        /// `hours` ago, or in the small hours the same share of today so far:
        /// still today, still in this order.
        func today(_ hours: Double) -> Date {
            let elapsed = now.timeIntervalSince(startOfToday)
            return now.addingTimeInterval(-(elapsed > 6 * 3600 ? hours * 3600 : elapsed * hours / 6))
        }
        /// `hour` o'clock, `days` days ago.
        func day(_ days: Int, at hour: Int) -> Date {
            calendar.date(byAdding: .hour, value: hour,
                          to: calendar.date(byAdding: .day, value: -days, to: startOfToday)!)!
        }
        func line(_ m: CommunityMember, _ kind: PracticeContentKind, _ id: Int, _ title: String,
                  _ category: PracticeCategory?, _ completedAt: Date,
                  likes: Int = 0, liked: Bool = false) -> CommunityActivity {
            CommunityActivity(id: UUID(), member: m, kind: kind, contentID: id, title: title,
                              category: category, completedAt: completedAt,
                              likeCount: likes, likedByMe: liked)
        }
        allActivity = [
            line(Self.alma,  .session,  11, "Confidence Boost",     .breathwork, today(0.2), likes: 3, liked: true),
            line(Self.me,    .exercise, 2,  "Morning Mobility",     nil,         today(1.5), likes: 1),
            line(Self.theo,  .session,  12, "Body Scan for Sleep",  .meditation, today(5),   likes: 1),
            line(Self.nia,   .recipe,   1,  "Golden Turmeric Broth", nil,        day(1, at: 21)),
            line(Self.mateo, .session,  13, "Shaking It Out",       .somatic,    day(1, at: 18)),
            line(Self.alma,  .exercise, 3,  "Core & Ground",        nil,         day(6, at: 12), likes: 2),
        ]
        notifications = [
            LikeNotification(id: UUID(), actor: Self.alma, playID: allActivity[1].id,
                             practiceTitle: "Morning Mobility", createdAt: today(0.7), readAt: nil),
            LikeNotification(id: UUID(), actor: Self.theo, playID: nil,
                             practiceTitle: "Core & Ground", createdAt: day(2, at: 10),
                             readAt: day(2, at: 11)),
        ]
        notificationsLoaded = true
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
        activityLoadedAt = [.all: .now, .friends: .now]
        friendshipsLoaded = true
        activityFailure = nil
        friendshipsFailure = nil
    }
    #endif
}
