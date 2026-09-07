import Foundation

enum AppError: LocalizedError {
    case configurationMissing
    case authFailure(Error)
    case networkFailure(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "The app isn't configured correctly. Please contact support."
        case .authFailure:
            return "Couldn't sign you in. Please try again."
        case .networkFailure:
            return "Couldn't connect. Check your connection and try again."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}

extension Error {
    /// True when this error is task cancellation, in either of the two shapes
    /// it actually arrives in.
    ///
    /// Every `catch is CancellationError` around a Supabase call was dead code:
    /// the SDK bottoms out in `URLSession`'s async API, which throws
    /// `URLError(.cancelled)` — not `CancellationError` — when the enclosing
    /// task is cancelled. So navigating away mid-fetch fell through to the real
    /// error path and the user was shown a failure for a request nobody was
    /// waiting on (mock retreats swapped in, "Couldn't load these sessions").
    ///
    /// Prefer `Task.isCancelled` where it's in scope; use this where only the
    /// error is.
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
