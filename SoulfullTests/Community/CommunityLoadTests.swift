//
//  CommunityLoadTests.swift
//  SoulfullTests
//
//  The Community tab's view model lives for the whole session, so when it
//  reads matters as much as what: a minute's freshness, then a quiet re-read
//  over the lines on screen; the Friends feed waiting for the friends it is
//  read by; nothing of one person's left for the next; and only what was
//  shown marked read. The feed, likes and friends against the live backend
//  are SoulfullUITests/CommunityTests.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Community loading")
struct CommunityLoadTests {

    /// The backend, scripted, with a clock the test moves by hand.
    @MainActor final class FakeCommunity {
        var now = Calendar.gregorian(in: "Europe/Madrid").at(2026, 9, 16, 12)
        var me: UUID? = UUID()
        var activity: [CommunityActivity] = []
        var friendships: [Friendship] = []
        var notifications: [LikeNotification] = []
        var activityError: (any Error)?
        var friendshipsError: (any Error)?
        var searchResults: [CommunityMember] = []
        /// What the next request, block or report throws, if anything.
        var writeError: (any Error)?

        private(set) var requestsSent: [UUID] = []
        private(set) var blocked: [UUID] = []
        private(set) var reports: [MemberReport] = []

        private(set) var activityReads: [[UUID]?] = []
        private(set) var friendshipReads = 0
        private(set) var notificationReads = 0
        private(set) var markedRead: [[UUID]] = []
        /// How many lines the feed was showing as each activity read began.
        private(set) var linesOnScreenAtRead: [Int] = []
        weak var vm: CommunityViewModel?

        func viewModel() -> CommunityViewModel {
            let vm = CommunityViewModel(backend: CommunityBackend(
                currentUserID: { self.me },
                fetchActivity: { ids in
                    self.activityReads.append(ids)
                    self.linesOnScreenAtRead.append(self.vm?.activity.count ?? -1)
                    if let error = self.activityError { throw error }
                    return self.activity
                },
                fetchFriendships: { _ in
                    self.friendshipReads += 1
                    if let error = self.friendshipsError { throw error }
                    return self.friendships
                },
                fetchNotifications: { _ in
                    self.notificationReads += 1
                    return self.notifications
                },
                markNotificationsRead: { _, ids in self.markedRead.append(ids) },
                searchMembers: { _ in self.searchResults },
                sendFriendRequest: { _, to in
                    if let error = self.writeError { throw error }
                    self.requestsSent.append(to)
                },
                block: { memberID, _ in
                    if let error = self.writeError { throw error }
                    self.blocked.append(memberID)
                },
                report: { report in
                    if let error = self.writeError { throw error }
                    self.reports.append(report)
                },
                now: { self.now }
            ))
            self.vm = vm
            return vm
        }

        func wait(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }

        func befriend(_ member: CommunityMember) {
            guard let me else { return }
            friendships.append(Friendship(requesterID: me, addresseeID: member.id, status: .accepted,
                                          createdAt: now, other: member, direction: .sent))
        }
    }

    func member(_ name: String) -> CommunityMember {
        CommunityMember(id: UUID(), displayName: name, avatarUrl: nil)
    }

    func line(by member: CommunityMember, _ title: String = "Body Scan") -> CommunityActivity {
        CommunityActivity(id: UUID(), member: member, kind: .session, contentID: 1, title: title,
                          category: .meditation, completedAt: .distantPast)
    }

    func like(from member: CommunityMember) -> LikeNotification {
        LikeNotification(id: UUID(), actor: member, playID: nil, practiceTitle: "Body Scan",
                         createdAt: .distantPast, readAt: nil)
    }

    // MARK: - Freshness

    @Test func comingBackWithinAMinuteShowsWhatIsThereWithoutReadingAgain() async {
        let fake = FakeCommunity()
        fake.activity = [line(by: member("Alma G."))]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        fake.wait(30)

        await vm.load(isMember: true)
        await vm.loadActivity()

        #expect(fake.activityReads.count == 1)
        #expect(fake.friendshipReads == 1)
        #expect(fake.notificationReads == 1)
    }

    @Test func comingBackAfterAMinuteReadsEverythingAgainOverTheLinesOnScreen() async {
        let fake = FakeCommunity()
        let alma = member("Alma G.")
        fake.activity = [line(by: alma)]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        fake.wait(61)
        fake.activity = [line(by: alma, "Shaking It Out"), line(by: alma)]

        await vm.load(isMember: true)

        #expect(fake.activityReads.count == 2)
        #expect(fake.friendshipReads == 2)
        #expect(fake.notificationReads == 2)
        #expect(fake.linesOnScreenAtRead == [0, 1], "The old line must stay up while the new read runs")
        #expect(vm.activity.count == 2)
        #expect(!vm.isAwaitingFeed)
    }

    @Test func aFailedReadIsRetriedWithoutWaitingOutTheMinute() async {
        let fake = FakeCommunity()
        fake.activityError = URLError(.notConnectedToInternet)
        let vm = fake.viewModel()
        await vm.load(isMember: false)
        #expect(vm.feedFailure == .offline)
        fake.activityError = nil
        fake.activity = [line(by: member("Theo R."))]
        fake.wait(5)

        await vm.loadActivity()

        #expect(fake.activityReads.count == 2)
        #expect(vm.feedFailure == nil)
        #expect(vm.activity.count == 1)
    }

    // MARK: - The Friends feed

    /// Right after signing in from the Friends gate: the scope task asks for
    /// the Friends feed before the friendships have arrived.
    @Test func theFriendsFeedWaitsForTheFriendsInsteadOfShowingAnEmptyOne() async throws {
        let fake = FakeCommunity()
        let alma = member("Alma G.")
        fake.befriend(alma)
        fake.activity = [line(by: alma)]
        let vm = fake.viewModel()
        await vm.load(isMember: false)
        vm.scope = .friends

        await vm.loadActivity()

        #expect(fake.activityReads.count == 1, "Only the All feed — the Friends feed can't be read yet")
        #expect(vm.isAwaitingFeed)
        #expect(!vm.activityLoaded.contains(.friends))

        await vm.load(isMember: true)

        let friendsRead = try #require(fake.activityReads.last ?? nil)
        #expect(friendsRead == [alma.id])
        #expect(!vm.isAwaitingFeed)
        #expect(vm.activity.count == 1)
    }

    @Test func aFailedFriendsReadIsTheFriendsFeedsFailureNotAnInvitationToAddFriends() async {
        let fake = FakeCommunity()
        let vm = fake.viewModel()
        await vm.load(isMember: false)
        vm.scope = .friends
        fake.friendshipsError = URLError(.notConnectedToInternet)

        await vm.load(isMember: true)

        #expect(vm.feedFailure == .offline)
        #expect(!vm.isAwaitingFeed)
        #expect(fake.activityReads.count == 1, "No Friends feed read without the friends")
    }

    @Test func aNewFriendMakesTheFriendsFeedOutOfDateInsideTheMinute() async throws {
        let fake = FakeCommunity()
        let alma = member("Alma G."), theo = member("Theo R.")
        fake.befriend(alma)
        let vm = fake.viewModel()
        await vm.load(isMember: false)
        vm.scope = .friends
        await vm.load(isMember: true)
        fake.befriend(theo)
        await vm.loadFriendships(force: true)

        await vm.loadActivity()

        #expect(fake.activityReads.count == 3)
        let friendsRead = try #require(fake.activityReads.last ?? nil)
        #expect(Set(friendsRead) == [alma.id, theo.id])
    }

    // MARK: - Between people

    /// A member signs out on the Friends filter, mid-search; a guest session
    /// takes their place on the same phone.
    @Test func theNextPersonStartsFromAClearScreen() async {
        let fake = FakeCommunity()
        let alma = member("Alma G.")
        fake.befriend(alma)
        fake.notifications = [like(from: alma)]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        vm.scope = .friends
        vm.searchQuery = "Th"
        fake.me = UUID()
        fake.friendships = []
        fake.notifications = []

        await vm.load(isMember: false)

        #expect(vm.scope == .all)
        #expect(vm.searchQuery.isEmpty)
        #expect(vm.searchResults.isEmpty)
        #expect(vm.friendships.isEmpty)
        #expect(!vm.friendshipsLoaded)
        #expect(vm.notifications.isEmpty)
        #expect(vm.actionError == nil)
        #expect(vm.busy.isEmpty)
    }

    // MARK: - Marking read

    @Test func onlyTheNotificationsThatWereShownAreMarkedRead() async throws {
        let fake = FakeCommunity()
        let seen = like(from: member("Alma G."))
        fake.notifications = [seen]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        let shown = Set(vm.notifications.map(\.id))
        let arrivedLater = like(from: member("Theo R."))
        fake.notifications = [arrivedLater, seen]
        await vm.loadNotifications(force: true)

        await vm.markRead(shown)

        #expect(fake.markedRead == [[seen.id]])
        #expect(vm.unreadCount == 1)
        let later = try #require(vm.notifications.first { $0.id == arrivedLater.id })
        #expect(later.isUnread, "A like that arrived after the list was shown hasn't been seen")
    }

    @Test func markingWhatIsAlreadyReadAsksNothingOfTheServer() async {
        let fake = FakeCommunity()
        let note = like(from: member("Alma G."))
        fake.notifications = [note]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        await vm.markRead([note.id])

        await vm.markRead([note.id])

        #expect(fake.markedRead.count == 1)
    }
}
