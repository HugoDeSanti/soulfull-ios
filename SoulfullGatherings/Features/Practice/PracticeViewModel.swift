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

@Observable @MainActor
final class PracticeViewModel {

    var sessions: [PracticeSession] = []
    var isLoading = false
    var loadError: String? = nil

    /// Finished loading and found nothing — the track exists but has no content
    /// yet. Distinct from `loadError`, which means the fetch itself failed.
    private(set) var didLoad = false

    var isEmpty: Bool { didLoad && sessions.isEmpty && loadError == nil }

    func load(category: PracticeCategory) async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        do {
            sessions = try await SupabaseService.shared.fetchPracticeSessions(category: category)
            didLoad = true
        } catch is CancellationError {
            // View was dismissed mid-fetch; leave existing data intact.
        } catch {
            sessions = []
            didLoad = true
            loadError = "Couldn't load these sessions. Please try again."
        }
    }
}
