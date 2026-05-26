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
