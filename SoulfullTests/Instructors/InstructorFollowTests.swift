//
//  InstructorFollowTests.swift
//  SoulfullTests
//
//  Following a guide. The button and the count move at once and go back if
//  the server says no; a guest and the guide themselves can't follow; asking
//  for what is already true does nothing — which is what makes the account
//  gate's replay after sign-in safe — and a read that started before a follow
//  never lands on top of it.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Following a guide")
struct InstructorFollowTests {

    /// A stand-in for `instructor_follows` + `instructor_social()`: ten people
    /// follow the guide before the test starts.
    @MainActor
    final class Server {
        let member = UUID()
        var signedIn = true
        var isMe = false
        var followedByMember = false
        var failure: Error?
        private(set) var followCalls = 0
        private(set) var unfollowCalls = 0
        /// What the page showed while the request was in flight.
        var onWrite: () -> Void = {}
        /// Holds the next read at its start, with the numbers as they were.
        var holdNextRead = false
        private(set) var heldRead: CheckedContinuation<Void, Never>?

        var social: InstructorSocial {
            InstructorSocial(followers: 10 + (followedByMember ? 1 : 0), following: 2,
                             followedByMe: followedByMember, isMe: isMe, faces: [])
        }

        func releaseRead() { heldRead?.resume(); heldRead = nil }

        var backend: InstructorProfileViewModel.Backend {
            .init(
                instructor: { id in Instructor(id: id, name: "Alma Guerra", title: nil, bio: nil, photoUrl: nil) },
                social: { _ in
                    let snapshot = self.social
                    if self.holdNextRead {
                        self.holdNextRead = false
                        await withCheckedContinuation { self.heldRead = $0 }
                    }
                    return snapshot
                },
                library: { _ in InstructorLibrary(programs: [], sessions: [], credits: [], library: .empty) },
                follow: { _, _ in
                    self.followCalls += 1
                    self.onWrite()
                    if let failure = self.failure { throw failure }
                    self.followedByMember = true
                },
                unfollow: { _, _ in
                    self.unfollowCalls += 1
                    self.onWrite()
                    if let failure = self.failure { throw failure }
                    self.followedByMember = false
                },
                userID: { self.signedIn ? self.member : nil }
            )
        }
    }

    private func loadedPage(_ server: Server) async -> InstructorProfileViewModel {
        let vm = InstructorProfileViewModel(instructorID: "alma-guerra", backend: server.backend)
        await vm.load()
        return vm
    }

    @Test func followingMovesTheButtonAndTheCountBeforeTheServerAnswers() async {
        let server = Server()
        let vm = await loadedPage(server)
        var duringRequest: InstructorSocial?
        server.onWrite = { duringRequest = vm.social }

        await vm.setFollowing(true)

        #expect(duringRequest?.followedByMe == true)
        #expect(duringRequest?.followers == 11)
        #expect(vm.social?.followedByMe == true)
        #expect(vm.social?.followers == 11)
        #expect(server.followCalls == 1)
    }

    @Test func unfollowingTakesTheCountBack() async {
        let server = Server()
        server.followedByMember = true
        let vm = await loadedPage(server)

        await vm.setFollowing(false)

        #expect(vm.social?.followedByMe == false)
        #expect(vm.social?.followers == 10)
        #expect(server.unfollowCalls == 1)
    }

    @Test func aRefusedFollowPutsEverythingBack() async {
        let server = Server()
        server.failure = URLError(.badServerResponse)
        let vm = await loadedPage(server)

        await vm.setFollowing(true)

        #expect(vm.social?.followedByMe == false)
        #expect(vm.social?.followers == 10)
        #expect(vm.followError == "That didn't go through. Please try again.")
        #expect(!vm.isFollowBusy)
    }

    @Test func anOfflineFollowSaysWhy() async {
        let server = Server()
        server.failure = URLError(.notConnectedToInternet)
        let vm = await loadedPage(server)

        await vm.setFollowing(true)

        #expect(vm.followError == "You're offline. Reconnect and try again.")
    }

    @Test func theNextFollowClearsTheLastError() async {
        let server = Server()
        server.failure = URLError(.badServerResponse)
        let vm = await loadedPage(server)
        await vm.setFollowing(true)

        server.failure = nil
        await vm.setFollowing(true)

        #expect(vm.followError == nil)
        #expect(vm.social?.followedByMe == true)
    }

    @Test func aGuestIsNeverSentToTheServer() async {
        let server = Server()
        server.signedIn = false
        let vm = await loadedPage(server)

        await vm.setFollowing(true)

        #expect(server.followCalls == 0)
        #expect(vm.social?.followedByMe == false)
        #expect(vm.social?.followers == 10)
    }

    @Test func aGuideCannotFollowThemselves() async {
        let server = Server()
        server.isMe = true
        let vm = await loadedPage(server)

        await vm.setFollowing(true)

        #expect(server.followCalls == 0)
        #expect(vm.social?.followers == 10)
    }

    /// The account gate replays "Follow" after sign-in — by which time the
    /// page may know the account already follows. A toggle would unfollow.
    @Test func askingForWhatIsAlreadyTrueDoesNothing() async {
        let server = Server()
        server.followedByMember = true
        let vm = await loadedPage(server)

        await vm.setFollowing(true)

        #expect(server.followCalls == 0)
        #expect(server.unfollowCalls == 0)
        #expect(vm.social?.followedByMe == true)
        #expect(vm.social?.followers == 11)
    }

    /// Signing in re-reads the page while the replayed follow is in flight.
    /// That read carries the numbers from before the follow, and must not
    /// flip the button back under the member's thumb.
    @Test func aReadThatStartedBeforeAFollowDoesNotUndoIt() async {
        let server = Server()
        let vm = await loadedPage(server)
        server.holdNextRead = true
        let staleRead = Task { await vm.refreshSocial() }
        for _ in 0..<100 where server.heldRead == nil { await Task.yield() }
        #expect(server.heldRead != nil)

        await vm.setFollowing(true)
        server.releaseRead()
        await staleRead.value

        #expect(vm.social?.followedByMe == true)
        #expect(vm.social?.followers == 11)
    }
}
