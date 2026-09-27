//
//  PresenceStore.swift
//  Soulfull Gatherings
//
//  "75.7k present" — who else is with a practice or a digital retreat. One
//  read of each RPC answers every row on every screen, so the lists don't
//  make a request per row; `PresenceLine` asks this store on appear and the
//  store decides whether that means the network.
//
//  Fails soft and silently: presence is atmosphere, not content. When it
//  can't be read the lines simply aren't there, and nothing else on the
//  screen waits for it.
//

import SwiftUI

@Observable @MainActor
final class PresenceStore {

    static let shared = PresenceStore()

    /// Keyed "session-4" / "journal-2" — `PracticeProgress.id`'s shape.
    private(set) var practices: [String: Presence] = [:]
    /// Keyed by program id.
    private(set) var programs: [String: Presence] = [:]

    private var loadedAt: Date?
    private var inFlight: Task<Void, Never>?

    /// A 24-hour window moves slowly; a minute of staleness is invisible and
    /// saves a request on every push and pop.
    private static let ttl: TimeInterval = 60

    func presence(kind: PracticeContentKind, contentID: Int) -> Presence? {
        #if DEBUG
        if Self.previewFixture { return loadedAt == nil ? nil : Self.fixture(seed: "\(kind.rawValue)-\(contentID)", faces: kind != .journal) }
        #endif
        return practices["\(kind.rawValue)-\(contentID)"]
    }

    func presence(programID: String) -> Presence? {
        #if DEBUG
        if Self.previewFixture { return loadedAt == nil ? nil : Self.fixture(seed: programID, faces: true) }
        #endif
        return programs[programID]
    }

    /// Cheap to call from every row: concurrent callers share one request,
    /// and a fresh read no-ops.
    func refresh(force: Bool = false) async {
        if let inFlight { await inFlight.value; return }
        if !force, let loadedAt, Date.now.timeIntervalSince(loadedAt) < Self.ttl { return }
        let task = Task { await load() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func load() async {
        #if DEBUG
        // The fixture still waits for a load, so the tests exercise the same
        // path live data takes. Returning it from the first frame is what hid
        // a PresenceLine that never started loading at all.
        if Self.previewFixture { loadedAt = .now; return }
        #endif
        async let p = try? SupabaseService.shared.fetchPracticePresence()
        async let g = try? SupabaseService.shared.fetchProgramPresence()
        let (practiceRows, programRows) = await (p, g)
        // Keep what we had rather than blanking the lines on a dropped request.
        if let practiceRows { practices = practiceRows }
        if let programRows { programs = programRows }
        if practiceRows == nil || programRows == nil {
            Log.data.error("Presence: couldn't read one or both counts")
        } else {
            loadedAt = .now
        }
    }

    // MARK: - DEBUG fixture

    #if DEBUG
    /// `-preview-presence`: every practice and program shows a count, so the
    /// badge can be seen before the live catalog has three people on anything.
    private static let previewFixture = CommandLine.arguments.contains("-preview-presence")

    private static func fixture(seed: String, faces: Bool) -> Presence {
        let counts = [75_700, 1_240, 312, 8, 4_950, 1_000_000]
        let sum = seed.utf8.reduce(0) { $0 &+ Int($1) }
        let people = [
            CommunityMember(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, displayName: "Alma G.", avatarUrl: nil),
            CommunityMember(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, displayName: "Theo R.", avatarUrl: nil),
            CommunityMember(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!, displayName: "Nia K.", avatarUrl: nil),
        ]
        return Presence(count: max(3, counts[sum % counts.count]), faces: faces ? people : [])
    }
    #endif
}
