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

    /// True when this device has no usable connection — as distinct from "we
    /// reached the network and something went wrong".
    ///
    /// The distinction is the whole point of the two failure states: telling
    /// someone on a train to "try again" is useless, and telling someone whose
    /// connection is fine to "check your connection" sends them chasing the
    /// wrong problem.
    ///
    /// Deliberately conservative. `timedOut` and `cannotConnectToHost` are NOT
    /// here: they are just as likely to mean our backend is down as that the
    /// user is offline, and those fall through to the generic message. Read off
    /// `NSError` rather than casting to `URLError`, because the Supabase SDK
    /// hands some failures back already bridged.
    var isOffline: Bool {
        let ns = self as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        switch ns.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed,
             NSURLErrorInternationalRoamingOff:
            return true
        default:
            return false
        }
    }
}
