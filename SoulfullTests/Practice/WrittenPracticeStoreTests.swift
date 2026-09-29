//
//  WrittenPracticeStoreTests.swift
//  SoulfullTests
//
//  The journal prompts, movement sequences and recipes come from tables, and
//  the store in front of them promises three things: offline says offline and
//  a failure at our end doesn't; a failed refresh never takes away a library
//  that loaded; and the last library read is kept for a launch with no
//  connection — but a kept copy is never taken as proof that something newer
//  doesn't exist, because a program day would close around it.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Written practice store")
struct WrittenPracticeStoreTests {

    private struct Offline: Error {}

    /// Answers each read with the next scripted result, and counts them.
    @MainActor final class ScriptedTables {
        var results: [Result<WrittenLibrary, any Error>]
        private(set) var reads = 0
        init(_ results: [Result<WrittenLibrary, any Error>]) { self.results = results }
        func fetch() throws -> WrittenLibrary {
            reads += 1
            return try results.removeFirst().get()
        }
    }

    /// A fresh file per test, in the test process's temporary directory.
    private let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("written-library-\(UUID().uuidString).json")

    private let live = Fixtures.library(journals: [1, 2], exercises: [1], recipes: [1, 2, 3])

    @Test func aReadIsTheLibraryAndItsAnswerIsAuthoritative() async {
        let store = WrittenPracticeStore(fetch: { [live] in live }, cacheURL: nil)
        #expect(!store.isAuthoritative)

        await store.refresh()

        #expect(store.library.recipes.map(\.id) == [1, 2, 3])
        #expect(store.status == .done)
        #expect(store.isAuthoritative)
    }

    @Test func offlineIsCalledOffline() async {
        let store = WrittenPracticeStore(fetch: { throw URLError(.notConnectedToInternet) }, cacheURL: nil)

        await store.refresh()

        #expect(store.status == .failed(offline: true))
        #expect(!store.isAuthoritative)
        #expect(store.library.isEmpty)
    }

    @Test func aFailureAtOurEndIsNotCalledOffline() async {
        let store = WrittenPracticeStore(fetch: { throw URLError(.badServerResponse) }, cacheURL: nil)

        await store.refresh()

        #expect(store.status == .failed(offline: false))
    }

    @Test func aFailedRefreshKeepsWhatLoaded() async {
        let tables = ScriptedTables([.success(live), .failure(URLError(.notConnectedToInternet))])
        let store = WrittenPracticeStore(fetch: { try tables.fetch() }, cacheURL: nil)
        await store.refresh()

        await store.refresh()

        #expect(tables.reads == 2)
        #expect(store.library.journals.map(\.id) == [1, 2])
        #expect(store.status == .done, "Still this launch's answer")
    }

    @Test func theLastReadIsThereForALaunchWithNoConnection() async {
        let first = WrittenPracticeStore(fetch: { [live] in live }, cacheURL: cacheURL)
        await first.refresh()

        let next = WrittenPracticeStore(fetch: { throw URLError(.notConnectedToInternet) }, cacheURL: cacheURL)
        await next.refresh()

        #expect(next.library.journals.map(\.id) == [1, 2])
        #expect(next.library.exercises.first?.steps.map(\.name) == ["Step"])
        #expect(!next.isAuthoritative, "A kept copy can't say what doesn't exist")
        try? FileManager.default.removeItem(at: cacheURL)
    }

    @Test func aCopyThatDoesNotDecodeIsIgnored() throws {
        try Data("not a library".utf8).write(to: cacheURL)

        let store = WrittenPracticeStore(fetch: { throw Offline() }, cacheURL: cacheURL)

        #expect(store.library.isEmpty)
        try? FileManager.default.removeItem(at: cacheURL)
    }
}
