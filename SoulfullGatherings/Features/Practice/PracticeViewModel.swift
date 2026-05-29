//
//  PracticeViewModel.swift
//  Soulfull Gatherings
//
//  Loads the on-demand sessions for one practice track from Supabase, falling
//  back to mock data while the `practice_sessions` table is being seeded.
//

import SwiftUI

@Observable @MainActor
final class PracticeViewModel {

    var sessions: [PracticeSession] = []
    var isLoading = false
    var loadError: String? = nil

    func load(category: PracticeCategory) async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        do {
            print("[PracticeViewModel] Fetching \(category.rawValue) sessions from Supabase…")
            sessions = try await SupabaseService.shared.fetchPracticeSessions(category: category)
            print("[PracticeViewModel] Fetched \(sessions.count) \(category.rawValue) sessions")
        } catch is CancellationError {
            // View was dismissed mid-fetch; leave existing data intact.
        } catch {
            // Table not seeded yet — fall back to mock so the UI is usable.
            print("[PracticeViewModel] fetch failed (\(error)); using mock data")
            sessions = PracticeSession.mock(for: category)
        }
    }
}
