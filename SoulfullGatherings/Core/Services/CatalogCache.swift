//
//  CatalogCache.swift
//  Soulfull Gatherings
//
//  The catalog's reads — retreats, digital retreats, practice tracks, the
//  written libraries, guides — kept for five minutes, and shared while one is
//  in flight. Member data is never kept here (CLAUDE.md, Backend).
//
//  It replaced six hand-written copies of the same check in
//  `SupabaseService`, none of which shared a read in flight: two screens
//  asking for the catalog in the same moment (Home's shelf and the tab behind
//  it, say) made two requests.
//

import Foundation

actor CatalogCache {

    enum Key: Hashable, Sendable {
        case retreats
        case programs
        case practiceCategories
        case practice(PracticeCategory)
        case instructors
        case writtenLibrary
    }

    private var stored: [Key: (value: any Sendable, at: Date)] = [:]
    private var running: [Key: Task<any Sendable, any Error>] = [:]
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    init(ttl: TimeInterval = 300, now: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttl
        self.now = now
    }

    /// What `key` holds if it was read within the last `ttl`; otherwise the
    /// read already under way for it, or a new one by `fetch`. A failure is
    /// never kept, so the next ask tries again.
    func value<Value: Sendable>(_ key: Key,
                                fetch: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let hit = stored[key], now().timeIntervalSince(hit.at) < ttl, let value = hit.value as? Value {
            return value
        }
        if let task = running[key], let value = try await task.value as? Value {
            return value
        }
        let task = Task<any Sendable, any Error> { try await fetch() }
        running[key] = task
        do {
            let value = try await task.value
            // Kept only if nothing cleared the cache while it was out: a read
            // that started before a sign-out mustn't fill the cache after it.
            if running[key] == task {
                running[key] = nil
                stored[key] = (value, now())
            }
            // One type per key, so this always holds; read again if it didn't.
            guard let typed = value as? Value else { return try await fetch() }
            return typed
        } catch {
            if running[key] == task { running[key] = nil }
            throw error
        }
    }

    /// Forgets everything, including reads still out (on sign-out, or a
    /// deliberate refresh).
    func clear() {
        stored.removeAll()
        running.removeAll()
    }
}
