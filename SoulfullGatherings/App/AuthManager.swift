import SwiftUI
@preconcurrency import Supabase

/// Manages Supabase Auth. Establishes an anonymous session on first launch
/// and restores it on subsequent launches. Injected into the environment
/// alongside AppState so any view can gate on `auth.isAuthenticated`.
@Observable @MainActor
final class AuthManager {

    enum State: Equatable {
        case initializing
        case authenticated
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.initializing, .initializing):   return true
            case (.authenticated, .authenticated): return true
            case (.failed(let a), .failed(let b)): return a == b
            default:                               return false
            }
        }
    }

    private(set) var state: State = .initializing

    var isAuthenticated: Bool { state == .authenticated }

    private let supabase: SupabaseClient

    init() {
        supabase = SupabaseService.shared.client
    }

    /// Restores an existing session or creates an anonymous one.
    /// Called once from `AppState.initializeAuth()` at launch.
    func initialize() async {
        do {
            _ = try await supabase.auth.session
            state = .authenticated
        } catch {
            await signInAnonymously()
        }
    }

    private func signInAnonymously() async {
        do {
            _ = try await supabase.auth.signInAnonymously()
            state = .authenticated
        } catch {
            let msg = AppError.authFailure(error).localizedDescription
            state = .failed(msg)
            print("[AuthManager] Anonymous sign-in failed: \(error)")
        }
    }
}
