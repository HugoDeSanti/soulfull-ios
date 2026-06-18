//
//  RetreatTripStore.swift
//  Soulfull Gatherings
//
//  Device-local persistence for the post-purchase retreat experience —
//  to-do completion and 1:1 guide-session bookings. Mirrors the Claude Design
//  prototype's `localStorage`: state lives only on this device for now. A real
//  cross-device sync would move to Supabase tables (see docs/PLAN-* for the
//  group-chat / installments follow-ups). State is keyed by retreat id so a
//  member can have separate trips.
//

import SwiftUI

@Observable @MainActor
final class RetreatTripStore {
    static let shared = RetreatTripStore()

    /// retreatID → set of completed to-do ids.
    private(set) var completedTodos: [Int: Set<String>]
    /// retreatID → (guide name → booked slot label).
    private(set) var bookedSessions: [Int: [String: String]]

    private let defaults: UserDefaults
    private static let todosKey = "sg.trip.todos"
    private static let sessionsKey = "sg.trip.sessions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Stored as plist-friendly [String: …] keyed by the retreat id string.
        let rawTodos = (defaults.dictionary(forKey: Self.todosKey) as? [String: [String]]) ?? [:]
        completedTodos = Dictionary(uniqueKeysWithValues: rawTodos.compactMap { key, ids in
            Int(key).map { ($0, Set(ids)) }
        })

        let rawSessions = (defaults.dictionary(forKey: Self.sessionsKey) as? [String: [String: String]]) ?? [:]
        bookedSessions = Dictionary(uniqueKeysWithValues: rawSessions.compactMap { key, map in
            Int(key).map { ($0, map) }
        })
    }

    // MARK: - To-do's

    func isDone(_ todoID: String, retreatID: Int) -> Bool {
        completedTodos[retreatID]?.contains(todoID) ?? false
    }

    func toggleTodo(_ todoID: String, retreatID: Int) {
        var set = completedTodos[retreatID] ?? []
        if set.contains(todoID) { set.remove(todoID) } else { set.insert(todoID) }
        completedTodos[retreatID] = set
        persistTodos()
    }

    // MARK: - 1:1 guide sessions

    func bookedSlot(guide: String, retreatID: Int) -> String? {
        bookedSessions[retreatID]?[guide]
    }

    func book(guide: String, slot: String, retreatID: Int) {
        var map = bookedSessions[retreatID] ?? [:]
        map[guide] = slot
        bookedSessions[retreatID] = map
        persistSessions()
    }

    func cancelBooking(guide: String, retreatID: Int) {
        guard var map = bookedSessions[retreatID] else { return }
        map.removeValue(forKey: guide)
        bookedSessions[retreatID] = map
        persistSessions()
    }

    // MARK: - Persistence

    private func persistTodos() {
        let raw = Dictionary(uniqueKeysWithValues: completedTodos.map { (String($0.key), Array($0.value)) })
        defaults.set(raw, forKey: Self.todosKey)
    }

    private func persistSessions() {
        let raw = Dictionary(uniqueKeysWithValues: bookedSessions.map { (String($0.key), $0.value) })
        defaults.set(raw, forKey: Self.sessionsKey)
    }
}
