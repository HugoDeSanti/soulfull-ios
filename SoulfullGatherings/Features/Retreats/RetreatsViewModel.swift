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
            // Graceful fallback: browse saved retreats rather than hit a dead
            // end. Filtered by `hasBegun` exactly like the server query — the
            // fixture used to go out unfiltered, so an offline user was shown
            // five retreats that had already finished, each with a price and a
            // live "Request a place" button.
            let fallback = Retreat.mock.filter { !$0.hasBegun }
            if retreats.isEmpty, !fallback.isEmpty {
                retreats = fallback
                activeIndex = 0
            } else {
                loadError = "Couldn't load retreats. Please try again."
            }
        }
    }
}
