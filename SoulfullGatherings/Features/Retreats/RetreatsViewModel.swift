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
            retreats = try await SupabaseService.shared.fetchRetreats()
            activeIndex = 0
        } catch where error.isCancellation {
            // View was dismissed mid-fetch; leave existing data intact.
            // `is CancellationError` never matched — the SDK surfaces
            // cancellation as URLError(.cancelled). See Error.isCancellation.
            // This one mattered most: the fallback below swapped in
            // `Retreat.mock`, so a quick back-navigation showed sample data.
        } catch {
            Log.data.error("Retreats fetch failed: \(error.localizedDescription)")
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
