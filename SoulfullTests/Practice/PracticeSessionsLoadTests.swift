//
//  PracticeSessionsLoadTests.swift
//  SoulfullTests
//
//  A media track's session list. An empty list only means "nothing here yet"
//  once a load has answered — before that the screen flashed it on every
//  open — and a refresh that fails over sessions already listed leaves them
//  standing rather than wiping them for an error.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Practice session list loading")
struct PracticeSessionsLoadTests {

    /// A fetch that answers with each result in turn, one per load.
    @MainActor
    final class Answers {
        var results: [Result<[PracticeSession], any Error>]
        init(_ results: [Result<[PracticeSession], any Error>]) { self.results = results }
        func next() throws -> [PracticeSession] { try results.removeFirst().get() }
    }

    func viewModel(_ results: Result<[PracticeSession], any Error>...) -> PracticeViewModel {
        let answers = Answers(results)
        return PracticeViewModel(fetchSessions: { _ in try answers.next() })
    }

    @Test func anEmptyListIsNotAnAnswerBeforeAnyLoad() {
        let vm = viewModel(.success([Fixtures.session(1)]))

        #expect(!vm.hasLoaded)
        #expect(!vm.isEmpty)
    }

    @Test func aLoadListsTheSessions() async {
        let vm = viewModel(.success([Fixtures.session(1), Fixtures.session(2)]))

        await vm.load(category: .breathwork)

        #expect(vm.sessions.map(\.id) == [1, 2])
        #expect(vm.hasLoaded)
        #expect(vm.loadFailure == nil)
        #expect(!vm.isLoading)
    }

    @Test func anEmptyTrackAfterALoadIsTheAnswer() async {
        let vm = viewModel(.success([]))

        await vm.load(category: .breathwork)

        #expect(vm.isEmpty)
    }

    @Test(arguments: [
        (URLError(.notConnectedToInternet), PracticeLoadFailure.offline),
        (URLError(.timedOut), .failed),
    ])
    func aFailedFirstLoadSaysWhy(_ error: URLError, _ failure: PracticeLoadFailure) async {
        let vm = viewModel(.failure(error))

        await vm.load(category: .breathwork)

        #expect(vm.hasLoaded)
        #expect(vm.loadFailure == failure)
        #expect(!vm.isEmpty)
    }

    @Test func aFailedRefreshKeepsTheSessionsAlreadyListed() async {
        let vm = viewModel(.success([Fixtures.session(1)]), .failure(URLError(.notConnectedToInternet)))
        await vm.load(category: .breathwork)

        await vm.load(category: .breathwork)

        #expect(vm.sessions.map(\.id) == [1])
        #expect(vm.loadFailure == nil)
    }

    @Test func aSuccessfulRetryClearsTheFailure() async {
        let vm = viewModel(.failure(URLError(.timedOut)), .success([Fixtures.session(1)]))
        await vm.load(category: .breathwork)

        await vm.load(category: .breathwork)

        #expect(vm.loadFailure == nil)
        #expect(vm.sessions.map(\.id) == [1])
    }

    /// Leaving the screen mid-fetch cancels it; nobody is waiting on that answer.
    @Test func aCancelledLoadHasNotAnswered() async {
        let vm = viewModel(.failure(URLError(.cancelled)))

        await vm.load(category: .breathwork)

        #expect(!vm.hasLoaded)
        #expect(vm.loadFailure == nil)
    }
}
