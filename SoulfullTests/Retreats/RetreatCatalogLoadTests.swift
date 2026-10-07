//
//  RetreatCatalogLoadTests.swift
//  SoulfullTests
//
//  The retreat catalog has no offline fallback — a sample catalog shown as the
//  real one is Guideline 2.1(a) "temporary content", and it once showed
//  finished retreats with live prices. A failed load says why instead, and a
//  refresh that fails over a catalog already on screen leaves it standing.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Retreat catalog loading")
struct RetreatCatalogLoadTests {

    /// Answers each load with the next scripted result.
    @MainActor final class ScriptedCatalog {
        var results: [Result<[Retreat], any Error>]
        init(_ results: [Result<[Retreat], any Error>]) { self.results = results }
        func fetch() throws -> [Retreat] { try results.removeFirst().get() }
    }

    func viewModel(_ results: Result<[Retreat], any Error>...) -> RetreatsViewModel {
        let catalog = ScriptedCatalog(results)
        return RetreatsViewModel(fetchRetreats: { try catalog.fetch() })
    }

    let catalog = [Fixtures.retreat(id: 1, name: "Mallorca"), Fixtures.retreat(id: 2, name: "Lapland")]

    @Test func aLoadShowsTheCatalogFromTheTop() async {
        let vm = viewModel(.success(catalog))
        vm.activeIndex = 1

        await vm.load()

        #expect(vm.retreats.map(\.name) == ["Mallorca", "Lapland"])
        #expect(vm.activeIndex == 0)
        #expect(vm.loadFailure == nil)
        #expect(!vm.isLoading)
    }

    @Test func offlineWithNothingLoadedSaysOfflineAndShowsNoSampleData() async {
        let vm = viewModel(.failure(URLError(.notConnectedToInternet)))

        await vm.load()

        #expect(vm.loadFailure == .offline)
        #expect(vm.retreats.isEmpty)
    }

    @Test func aFailureThatIsNotOfflineIsCalledOurs() async {
        let vm = viewModel(.failure(URLError(.timedOut)))

        await vm.load()

        #expect(vm.loadFailure == .failed)
    }

    @Test func aFailedRefreshLeavesTheCatalogOnScreen() async {
        let vm = viewModel(.success(catalog), .failure(URLError(.badServerResponse)))
        await vm.load()

        await vm.load()

        #expect(vm.retreats.count == 2)
        #expect(vm.loadFailure == nil)
    }

    // MARK: - Empty is an answer, not a starting state

    /// The screen draws before its load starts. An empty catalog then must not
    /// read as "none announced", or the tab flashes its empty state.
    @Test func anEmptyCatalogIsNotAnAnswerBeforeAnyLoad() {
        let vm = viewModel()

        #expect(!vm.hasLoaded)
        #expect(vm.retreats.isEmpty)
    }

    @Test(arguments: [
        Result<[Retreat], any Error>.success([]),
        .failure(URLError(.notConnectedToInternet)),
        .failure(URLError(.badServerResponse)),
    ])
    func aLoadThatAnswersCountsAsLoaded(_ result: Result<[Retreat], any Error>) async {
        let vm = viewModel(result)

        await vm.load()

        #expect(vm.hasLoaded)
    }

    /// Navigating away mid-fetch cancels it; nobody is waiting on that answer.
    @Test func aCancelledLoadHasNotAnswered() async {
        let vm = viewModel(.failure(URLError(.cancelled)))

        await vm.load()

        #expect(!vm.hasLoaded)
        #expect(vm.loadFailure == nil)
    }

    // MARK: - Coming back to the tab

    /// The tab reloads every time it comes back. The stack has to stay on the
    /// retreat the member left it on.
    @Test func aReloadKeepsTheRetreatInFocus() async {
        let vm = viewModel(.success(catalog), .success(catalog))
        await vm.load()
        vm.activeIndex = 1

        await vm.load()

        #expect(vm.active?.name == "Lapland")
    }

    @Test func aReloadFollowsTheFocusedRetreatToItsNewPlace() async {
        let reordered = [Fixtures.retreat(id: 3, name: "Kyoto")] + catalog
        let vm = viewModel(.success(catalog), .success(reordered))
        await vm.load()
        vm.activeIndex = 1

        await vm.load()

        #expect(vm.activeIndex == 2)
        #expect(vm.active?.name == "Lapland")
    }

    @Test func aReloadWithoutTheFocusedRetreatStartsFromTheTop() async {
        let vm = viewModel(.success(catalog), .success([Fixtures.retreat(id: 1, name: "Mallorca")]))
        await vm.load()
        vm.activeIndex = 1

        await vm.load()

        #expect(vm.activeIndex == 0)
    }
}
