import SwiftUI

@Observable @MainActor
final class RetreatsViewModel {

    var retreats: [Retreat] = []
    var isLoading = false
    var loadError: String? = nil
    var activeIndex: Int = 0

    var active: Retreat? {
        retreats.indices.contains(activeIndex) ? retreats[activeIndex] : nil
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        do {
            print("[RetreatsViewModel] Fetching retreats from Supabase…")
            retreats = try await SupabaseService.shared.fetchRetreats()
            activeIndex = 0
            print("[RetreatsViewModel] Fetched \(retreats.count) retreats")
        } catch is CancellationError {
            // View was dismissed mid-fetch; leave existing data intact.
        } catch {
            print("[RetreatsViewModel] fetchRetreats failed: \(error)")
            // Graceful fallback (same pattern as practice sessions): browse
            // sample retreats rather than a dead end; reserve still requires
            // the backend.
            if retreats.isEmpty {
                retreats = Retreat.mock
                activeIndex = 0
            } else {
                loadError = "Couldn't load retreats. Please try again."
            }
        }
    }
}
