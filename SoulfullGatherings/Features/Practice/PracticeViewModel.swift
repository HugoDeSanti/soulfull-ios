//
//  PracticeViewModel.swift
//  Soulfull Gatherings
//
//  Loads the on-demand sessions for one practice track from Supabase.
//
//  There is deliberately NO mock fallback. The mocks pointed at public sample
//  media (Big Buck Bunny, a stock 15-second MP3) which, shipped, is a Guideline
//  2.1 rejection — a wellness app playing a cartoon rabbit. An unseeded or
//  unreachable track now reports emptiness honestly and the UI says so.
//

import SwiftUI

/// Why a track's sessions couldn't be listed. Worded like the written
/// libraries' `WrittenLibraryPlaceholder`, so every Practice list says the
/// same thing about the same problem.
enum PracticeLoadFailure: Equatable {
    /// The device can't get out. Retrying changes nothing until that does.
    case offline
    /// We reached the network and it failed anyway.
    case failed

    init(offline: Bool) { self = offline ? .offline : .failed }

    var title: String {
        switch self {
        case .offline: "No internet connection"
        case .failed:  "Couldn't load the sessions"
        }
    }

    var detail: String {
        switch self {
        case .offline: "You'll need to be online to load the sessions. Reconnect and try again."
        case .failed:  "Something went wrong at our end. Please try again in a moment."
        }
    }

    var systemImage: String {
        switch self {
        case .offline: "wifi.slash"
        case .failed:  "exclamationmark.circle"
        }
    }
}

@Observable @MainActor
final class PracticeViewModel {

    var sessions: [PracticeSession] = []
    var isLoading = false
    /// Set only when a load failed with nothing already listed. A refresh that
    /// fails over loaded sessions leaves them standing — they were wiped, and
    /// the list swapped for an error, every time the tab came back offline.
    var loadFailure: PracticeLoadFailure? = nil
    /// A load has answered, with sessions or a failure. Until then an empty
    /// list means "not here yet", not "none yet": the screen showed "Nothing
    /// here yet" for the frame before its first load began. A cancelled load
    /// doesn't count.
    private(set) var hasLoaded = false

    /// The track exists but has no content yet. Distinct from `loadFailure`,
    /// which means the fetch itself failed.
    var isEmpty: Bool { hasLoaded && sessions.isEmpty && loadFailure == nil }

    /// The session read. Injectable so the loading states can be tested
    /// without a network (`SoulfullTests/PracticeSessionsLoadTests`); the app
    /// always uses the default.
    private let fetchSessions: @MainActor (PracticeCategory) async throws -> [PracticeSession]

    init(fetchSessions: @escaping @MainActor (PracticeCategory) async throws -> [PracticeSession] = {
        try await SupabaseService.shared.fetchPracticeSessions(category: $0)
    }) {
        self.fetchSessions = fetchSessions
    }

    func load(category: PracticeCategory) async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await fetchSessions(category)
            loadFailure = nil
            hasLoaded = true
        } catch where error.isCancellation {
            // View was dismissed mid-fetch; leave existing data intact.
            // `is CancellationError` never matched — the SDK surfaces
            // cancellation as URLError(.cancelled). See Error.isCancellation.
        } catch {
            Log.data.error("Practice sessions fetch failed: \(error.localizedDescription)")
            if sessions.isEmpty { loadFailure = PracticeLoadFailure(offline: error.isOffline) }
            hasLoaded = true
        }
    }
}
