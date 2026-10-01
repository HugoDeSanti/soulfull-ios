//
//  ProgramCatalogLoadTests.swift
//  SoulfullTests
//
//  The Digital Retreats tab draws before its catalog load has started. An
//  empty catalog only means "none yet" once a load has answered; before that
//  the screen showed "New digital retreats are on their way" for a frame
//  every time it opened.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Program catalog loading")
struct ProgramCatalogLoadTests {

    /// Answers each load with the next scripted result.
    @MainActor final class ScriptedCatalog {
        var results: [Result<[Program], any Error>]
        init(_ results: [Result<[Program], any Error>]) { self.results = results }
        func fetch() throws -> [Program] { try results.removeFirst().get() }
    }

    func viewModel(_ results: Result<[Program], any Error>...) -> ProgramsViewModel {
        let catalog = ScriptedCatalog(results)
        return ProgramsViewModel(fetchPrograms: { try catalog.fetch() })
    }

    let program = Program(id: "finding-ground", title: "Finding Ground", lead: "Alma Guerra",
                          days: 7, imageUrl: "")

    @Test func anEmptyCatalogIsNotAnAnswerBeforeAnyLoad() {
        let vm = viewModel(.success([program]))

        #expect(!vm.hasLoaded)
        #expect(vm.programs.isEmpty)
    }

    @Test func aLoadShowsTheCatalog() async {
        let vm = viewModel(.success([program]))

        await vm.load()

        #expect(vm.programs.map(\.id) == ["finding-ground"])
        #expect(vm.hasLoaded)
        #expect(vm.loadFailure == nil)
        #expect(!vm.isLoading)
    }

    @Test func anEmptyCatalogAfterALoadIsTheAnswer() async {
        let vm = viewModel(.success([]))

        await vm.load()

        #expect(vm.hasLoaded)
        #expect(vm.loadFailure == nil)
    }

    @Test(arguments: [
        (URLError(.notConnectedToInternet), ProgramsLoadFailure.offline),
        (URLError(.timedOut), .failed),
    ])
    func aFailedLoadAnswersWithWhy(_ error: URLError, _ failure: ProgramsLoadFailure) async {
        let vm = viewModel(.failure(error))

        await vm.load()

        #expect(vm.hasLoaded)
        #expect(vm.loadFailure == failure)
        #expect(vm.programs.isEmpty)
    }

    // MARK: - Coming back to the tab

    /// The tab lives for the whole session and reads again each time it
    /// appears. A load-once guard kept the first catalog for days, so a program
    /// published since never reached it.
    @Test func aReloadPicksUpANewlyPublishedProgram() async {
        let next = Program(id: "coming-home", title: "Coming Home", lead: "Alma Guerra",
                           days: 5, imageUrl: "")
        let vm = viewModel(.success([program]), .success([program, next]))
        await vm.load()

        await vm.load()

        #expect(vm.programs.map(\.id) == ["finding-ground", "coming-home"])
    }

    @Test func aFailedReloadLeavesTheCatalogOnScreen() async {
        let vm = viewModel(.success([program]), .failure(URLError(.notConnectedToInternet)))
        await vm.load()

        await vm.load()

        #expect(vm.programs.map(\.id) == ["finding-ground"])
        #expect(vm.loadFailure == nil)
    }

    /// Leaving the tab mid-fetch cancels it; nobody is waiting on that answer.
    @Test func aCancelledLoadHasNotAnswered() async {
        let vm = viewModel(.failure(URLError(.cancelled)))

        await vm.load()

        #expect(!vm.hasLoaded)
        #expect(vm.loadFailure == nil)
    }
}
