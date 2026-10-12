//
//  CatalogCacheTests.swift
//  SoulfullTests
//
//  The catalog's reads: kept five minutes, shared while one is in flight,
//  never kept when they fail, and never kept when the cache was cleared while
//  they were out (a sign-out). No network: the fetches are counters.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Catalog cache")
struct CatalogCacheTests {

    /// Counts reads, and can hold one open until told to answer.
    actor FakeCatalog {
        private(set) var reads = 0
        private var gate: CheckedContinuation<Void, Never>?
        private var holding = false
        var failNext = false

        func holdNextRead() { holding = true }

        func release() {
            gate?.resume()
            gate = nil
        }

        var isWaiting: Bool { gate != nil }

        func read() async throws -> [String] {
            reads += 1
            if failNext {
                failNext = false
                throw URLError(.notConnectedToInternet)
            }
            if holding {
                holding = false
                await withCheckedContinuation { gate = $0 }
            }
            return ["mallorca", "bali"]
        }

        func setFailNext() { failNext = true }
    }

    /// A clock the test moves by hand.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var current = Calendar.gregorian(in: "Europe/Madrid").at(2026, 9, 16, 12)
        var now: Date { lock.withLock { current } }
        func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
    }

    func waitUntilWaiting(_ fake: FakeCatalog) async {
        while await !fake.isWaiting { await Task.yield() }
    }

    @Test func aRepeatWithinFiveMinutesReadsNothing() async throws {
        let fake = FakeCatalog(), clock = Clock()
        let cache = CatalogCache(ttl: 300, now: { clock.now })

        _ = try await cache.value(.retreats) { try await fake.read() }
        clock.advance(299)
        let again = try await cache.value(.retreats) { try await fake.read() }

        #expect(again == ["mallorca", "bali"])
        #expect(await fake.reads == 1)
    }

    @Test func afterFiveMinutesItReadsAgain() async throws {
        let fake = FakeCatalog(), clock = Clock()
        let cache = CatalogCache(ttl: 300, now: { clock.now })

        _ = try await cache.value(.retreats) { try await fake.read() }
        clock.advance(301)
        _ = try await cache.value(.retreats) { try await fake.read() }

        #expect(await fake.reads == 2)
    }

    /// The copies this replaced each made their own request.
    @Test func twoAsksAtOnceShareOneRead() async throws {
        let fake = FakeCatalog()
        let cache = CatalogCache()
        await fake.holdNextRead()

        async let first = cache.value(.programs) { try await fake.read() }
        await waitUntilWaiting(fake)
        async let second = cache.value(.programs) { try await fake.read() }
        // Let the second ask reach the cache and join the first.
        for _ in 0..<50 { await Task.yield() }
        await fake.release()

        #expect(try await first == ["mallorca", "bali"])
        #expect(try await second == ["mallorca", "bali"])
        #expect(await fake.reads == 1)
    }

    @Test func aFailedReadIsNotKept() async throws {
        let fake = FakeCatalog()
        let cache = CatalogCache()
        await fake.setFailNext()

        await #expect(throws: URLError.self) {
            try await cache.value(.instructors) { try await fake.read() }
        }
        let next = try await cache.value(.instructors) { try await fake.read() }

        #expect(next == ["mallorca", "bali"])
        #expect(await fake.reads == 2)
    }

    @Test func eachKeyIsKeptApart() async throws {
        let fake = FakeCatalog()
        let cache = CatalogCache()

        _ = try await cache.value(.practice(.breathwork)) { try await fake.read() }
        _ = try await cache.value(.practice(.meditation)) { try await fake.read() }

        #expect(await fake.reads == 2)
    }

    /// A read that set off before a sign-out answers after it: it reaches who
    /// asked, but mustn't fill the cleared cache.
    @Test func aReadThatAnswersAfterAClearIsNotKept() async throws {
        let fake = FakeCatalog()
        let cache = CatalogCache()
        await fake.holdNextRead()

        async let early = cache.value(.retreats) { try await fake.read() }
        await waitUntilWaiting(fake)
        await cache.clear()
        await fake.release()
        _ = try await early
        _ = try await cache.value(.retreats) { try await fake.read() }

        #expect(await fake.reads == 2)
    }
}
