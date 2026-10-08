//
//  CommunitySafetyTests.swift
//  SoulfullTests
//
//  Block, Report and the friend-request cooldown (0028) — Guideline 1.2's
//  tools, as the app holds them: a block takes someone off every list at once
//  and puts everything back if the server refuses; a read that set off before
//  the block can't bring them back; a report can't go without a reason; a
//  request inside the cooldown says why instead of "try again". The server's
//  side (RLS, the views, the triggers) is verified live per 0028's header; the
//  screens are SoulfullUITests/MemberSafetyTests.
//

import Foundation
import Testing
@preconcurrency import Supabase
@testable import SoulfullGatherings

@MainActor
@Suite("Community safety")
struct CommunitySafetyTests {

    typealias Fake = CommunityLoadTests.FakeCommunity

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

    func friendship(_ fake: Fake, with member: CommunityMember, accepted: Bool = true) -> Friendship {
        Friendship(requesterID: member.id, addresseeID: fake.me!, status: accepted ? .accepted : .pending,
                   createdAt: .distantPast, other: member, direction: .received)
    }

    // MARK: - Block

    @Test func blockingAMemberTakesThemOffEveryListAtOnce() async {
        let fake = Fake()
        let alma = member("Alma G."), theo = member("Theo R.")
        fake.activity = [line(by: alma), line(by: theo), line(by: theo, "Shaking It Out")]
        fake.friendships = [friendship(fake, with: theo)]
        fake.notifications = [like(from: theo), like(from: alma)]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        // What the server answers once the block has landed.
        fake.activity = [line(by: alma)]
        fake.friendships = []

        let held = await vm.block(theo)

        #expect(held)
        #expect(fake.blocked == [theo.id])
        #expect(vm.activity.map(\.member.id) == [alma.id])
        #expect(vm.friendships.isEmpty)
        #expect(vm.notifications.map(\.actor?.id) == [alma.id])
        #expect(vm.actionError == nil)
    }

    @Test func aRefusedBlockPutsEverythingBackAndSaysSo() async {
        let fake = Fake()
        let theo = member("Theo R.")
        fake.activity = [line(by: theo)]
        fake.friendships = [friendship(fake, with: theo)]
        fake.notifications = [like(from: theo)]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        fake.writeError = URLError(.notConnectedToInternet)

        let held = await vm.block(theo)

        #expect(!held)
        #expect(vm.activity.count == 1)
        #expect(vm.friendships.count == 1)
        #expect(vm.notifications.count == 1)
        #expect(vm.hiddenMembers.isEmpty)
        #expect(vm.actionError?.contains("offline") == true)
    }

    @Test func aReadThatAnswersAfterTheBlockStillLeavesThemOut() async {
        let fake = Fake()
        let theo = member("Theo R.")
        fake.activity = [line(by: theo)]
        fake.searchResults = [theo]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        await vm.block(theo)
        // A read that set off before the block reached the server.
        fake.friendships = [friendship(fake, with: theo, accepted: false)]
        fake.notifications = [like(from: theo)]
        fake.wait(61)

        await vm.load(isMember: true)

        #expect(vm.activity.isEmpty)
        #expect(vm.incomingRequests.isEmpty)
        #expect(vm.notifications.isEmpty)
        #expect(vm.unreadCount == 0)
    }

    @Test func noOneCanBlockThemselves() async {
        let fake = Fake()
        let me = CommunityMember(id: fake.me!, displayName: "Hugo D.", avatarUrl: nil)
        fake.activity = [line(by: me)]
        let vm = fake.viewModel()
        await vm.load(isMember: true)

        let held = await vm.block(me)

        #expect(!held)
        #expect(fake.blocked.isEmpty)
        #expect(vm.activity.count == 1)
    }

    @Test func aBlockedMembersReadIsGoneFromSearchToo() async throws {
        let fake = Fake()
        let theo = member("Theo R."), nia = member("Nia")
        fake.searchResults = [theo, nia]
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        await vm.block(theo)

        vm.searchQuery = "the"
        try await Task.sleep(for: .milliseconds(500))

        #expect(vm.searchResults.map(\.id) == [nia.id])
    }

    // MARK: - Friend request cooldown

    @Test func aRequestInsideTheCooldownSaysWhyAndLeavesNoPendingRow() async {
        let fake = Fake()
        let mateo = member("Mateo V.")
        let vm = fake.viewModel()
        await vm.load(isMember: true)
        fake.writeError = PostgrestError(hint: "A declined request can be sent again 30 days after it was declined.",
                                         code: "P0001", message: "friend_request_cooldown")

        await vm.sendRequest(to: mateo)

        #expect(vm.friendships.isEmpty)
        #expect(vm.standing(for: mateo.id) == .none)
        #expect(vm.actionError == "You can send Mateo V. another request 30 days after your last one was declined.")
    }

    @Test(arguments: [
        (PostgrestError(code: "P0001", message: "friend_request_cooldown") as any Error, true),
        (PostgrestError(code: "P0001", message: "something else") as any Error, false),
        (PostgrestError(code: "42501", message: "new row violates row-level security policy") as any Error, false),
        (URLError(.notConnectedToInternet) as any Error, false),
    ])
    func onlyTheCooldownReadsAsTheCooldown(error: any Error, isCooldown: Bool) {
        #expect(error.isFriendRequestCooldown == isCooldown)
    }

    @Test func otherFailedRequestsOfferTheRightNextStep() {
        let mateo = member("Mateo V.")

        let offline = CommunityViewModel.friendActionMessage(for: URLError(.notConnectedToInternet), about: mateo)
        let ours = CommunityViewModel.friendActionMessage(for: URLError(.badServerResponse), about: mateo)

        #expect(offline == "You're offline. Reconnect and try again.")
        #expect(ours == "That didn't go through. Please try again.")
    }

    // MARK: - Report

    @Test func aReportNeedsAReason() {
        let report = MemberReport(reportedID: UUID(), playID: nil, reason: nil, details: "They were rude")

        #expect(report == nil)
    }

    @Test func theNoteIsTrimmedCappedAndLeftOutWhenEmpty() throws {
        let long = String(repeating: "a", count: MemberReport.maxDetails + 40)

        let blank = try #require(MemberReport(reportedID: UUID(), playID: nil, reason: .spam, details: "  \n "))
        let capped = try #require(MemberReport(reportedID: UUID(), playID: nil, reason: .other, details: "  " + long))

        #expect(blank.details == nil)
        #expect(capped.details?.count == MemberReport.maxDetails)
        #expect(capped.details?.first == "a")
    }

    @Test func aReportIsSentInTheShapeTheFunctionReads() throws {
        let reported = UUID(), play = UUID()
        let report = try #require(MemberReport(reportedID: reported, playID: play, reason: .photo, details: "x"))

        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])

        #expect(json["reported_id"] as? String == reported.uuidString)
        #expect(json["play_id"] as? String == play.uuidString)
        #expect(json["reason"] as? String == "photo")
        #expect(json["details"] as? String == "x")
    }

    @Test func aReportGoesToTheTeamAndAFailureReachesTheSheet() async throws {
        let fake = Fake()
        let vm = fake.viewModel()
        let report = try #require(MemberReport(reportedID: UUID(), playID: nil, reason: .harassment, details: ""))

        try await vm.report(report)
        fake.writeError = URLError(.notConnectedToInternet)
        await #expect(throws: URLError.self) { try await vm.report(report) }

        #expect(fake.reports == [report])
    }
}

@MainActor
@Suite("Blocked members")
struct BlockedMembersTests {

    @Test func unblockingTakesThemOffTheList() async {
        let sam = CommunityMember(id: UUID(), displayName: "Sam K.", avatarUrl: nil)
        let ana = CommunityMember(id: UUID(), displayName: "Ana P.", avatarUrl: nil)
        var unblocked: [UUID] = []
        let vm = BlockedMembersViewModel(fetch: { [sam, ana] }, unblock: { unblocked.append($0) })
        await vm.load()

        await vm.unblock(sam)

        #expect(vm.members == [ana])
        #expect(unblocked == [sam.id])
    }

    @Test func aRefusedUnblockPutsThemBackWhereTheyWere() async {
        let sam = CommunityMember(id: UUID(), displayName: "Sam K.", avatarUrl: nil)
        let ana = CommunityMember(id: UUID(), displayName: "Ana P.", avatarUrl: nil)
        let vm = BlockedMembersViewModel(fetch: { [sam, ana] },
                                         unblock: { _ in throw URLError(.badServerResponse) })
        await vm.load()

        await vm.unblock(sam)

        #expect(vm.members == [sam, ana])
        #expect(vm.actionError == "We couldn't unblock Sam K. just now. Please try again.")
    }

    @Test func emptyOnlyCountsOnceTheListHasAnswered() async {
        let vm = BlockedMembersViewModel(fetch: { throw URLError(.notConnectedToInternet) }, unblock: { _ in })

        await vm.load()

        #expect(!vm.hasLoaded)
        #expect(vm.failure == .offline)
    }
}

@MainActor
@Suite("Practice safety notes")
struct PracticeSafetyNoteTests {

    @Test(arguments: PracticeCategory.allCases)
    func breathworkAndSomaticSayHowToStaySafe(category: PracticeCategory) {
        let needsOne = category != .meditation

        #expect((category.safetyNote != nil) == needsOne)
        #expect((category.safetyReminder != nil) == needsOne)
        if let note = category.safetyNote {
            #expect(note.contains("isn't medical"))
            #expect(note.contains("doctor"))
        }
    }
}
