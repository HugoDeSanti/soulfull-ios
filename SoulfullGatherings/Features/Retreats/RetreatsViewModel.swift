import SwiftUI

/// Why the retreat catalog is empty. Shared by `RetreatsViewModel` and
/// `HomeViewModel` so both surfaces say the same thing.
///
/// There is **no offline fallback.** `Retreat.mock` used to stand in whenever
/// the fetch failed, which meant a user with no signal was shown a catalog of
/// retreats — with prices and a live "Request a place" button — that had in
/// fact already happened. Guideline 2.1(a) is explicit that "placeholder text,
/// empty websites, and other temporary content should be scrubbed before
/// submission", and a sample catalog presented as the real one is exactly that.
/// Say what is wrong instead. `Retreat.mock` survives only for SwiftUI previews
/// and the DEBUG `-preview-*` screens.
enum RetreatsLoadFailure: Equatable {
    /// The device can't get out. Retrying changes nothing until that does.
    case offline
    /// We reached the network and it failed anyway.
    case failed

    var title: String {
        switch self {
        case .offline: "No internet connection"
        case .failed:  "Couldn't load retreats"
        }
    }

    var detail: String {
        switch self {
        case .offline:
            "You'll need to be online to browse our retreats. Reconnect and try again."
        case .failed:
            "Something went wrong at our end. Please try again in a moment."
        }
    }
}

@Observable @MainActor
final class RetreatsViewModel {

    var retreats: [Retreat] = []
    var isLoading = false
    var loadFailure: RetreatsLoadFailure? = nil
    /// A load has answered, with retreats or a failure. Until then an empty
    /// catalog means "not here yet", not "none announced": a screen that showed
    /// its empty state on the first frame flashed "New gatherings are on their
    /// way" every time the tab opened. A cancelled load doesn't count.
    private(set) var hasLoaded = false
    var activeIndex: Int = 0

    var active: Retreat? {
        retreats.indices.contains(activeIndex) ? retreats[activeIndex] : nil
    }

    /// The catalog read. Injectable so the failure handling below can be
    /// tested without a network (`SoulfullTests/RetreatCatalogLoadTests`);
    /// the app always uses the default.
    private let fetchRetreats: @MainActor () async throws -> [Retreat]

    init(fetchRetreats: @escaping @MainActor () async throws -> [Retreat] = {
        try await SupabaseService.shared.fetchRetreats()
    }) {
        self.fetchRetreats = fetchRetreats
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        loadFailure = nil
        do {
            let fetched = try await fetchRetreats()
            // A reload — the tab coming back — keeps the retreat in focus, so the
            // stack doesn't jump back to the top under the member. The first
            // load, or one that no longer has that retreat, starts at the top.
            let focused = active?.id
            retreats = fetched
            activeIndex = fetched.firstIndex { $0.id == focused } ?? 0
            hasLoaded = true
        } catch where error.isCancellation {
            // View was dismissed mid-fetch; leave existing data intact.
            // `is CancellationError` never matched — the SDK surfaces
            // cancellation as URLError(.cancelled). See Error.isCancellation.
            // This one mattered: the fallback here used to swap in
            // `Retreat.mock`, so a quick back-navigation showed sample data.
        } catch {
            Log.data.error("Retreats fetch failed: \(error.localizedDescription)")
            // Only strand the screen if we have nothing to show. A refresh that
            // fails over an already-loaded catalog leaves it standing.
            if retreats.isEmpty {
                loadFailure = error.isOffline ? .offline : .failed
            }
            hasLoaded = true
        }
    }
}
