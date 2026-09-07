//
//  AppleSignInButton.swift
//  Soulfull Gatherings
//
//  The Sign in with Apple control, shared by the onboarding account gate and
//  the You-tab account sheet. Pure UI: it produces the credential (or an error)
//  and hands it back — the caller owns the AuthManager / profile work.
//
//  Apple is the only third-party identity provider the app offers. Google was
//  built and then deliberately removed (2026-09-03) rather than shipped, so
//  there is no `ASWebAuthenticationSession` flow and no GoogleSignIn dependency.
//

import AuthenticationServices
import CryptoKit
import SwiftUI

/// Raised when Apple returns an authorization we can't turn into a Supabase
/// credential (no identity token, or an unexpected credential type).
struct SocialSignInError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct AppleSignInButton: View {
    var disabled: Bool = false
    /// Raw (un-hashed) nonce comes back alongside the token — Supabase needs it
    /// to verify the `nonce` claim Apple embedded in the signed token.
    let onCredential: (_ idToken: String, _ nonce: String, _ fullName: String?) -> Void
    let onFailure: (Error) -> Void

    /// One nonce per authorization attempt; rotated in `onCompletion`.
    @State private var nonce = AppleNonce.make()

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
            // Apple signs the *hash*; Supabase re-hashes the raw value we send.
            request.nonce = AppleNonce.sha256(nonce)
        } onCompletion: { result in
            let used = nonce
            nonce = AppleNonce.make()
            handle(result, nonce: used)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 54)
        .clipShape(Capsule())
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
        .animation(.easeInOut(duration: 0.2), value: disabled)
    }

    private func handle(_ result: Result<ASAuthorization, Error>, nonce: String) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                onFailure(SocialSignInError("Apple didn't return a usable sign-in token. Please try again."))
                return
            }
            // Apple only sends the name on the very first authorization; it's nil
            // (and `formatted()` empty) every time after that.
            let name = credential.fullName?.formatted()
            onCredential(token, nonce, (name?.isEmpty ?? true) ? nil : name)
        case .failure(let error):
            onFailure(error)
        }
    }
}

// MARK: - Nonce

/// Sign in with Apple replay protection: the request carries `sha256(nonce)`,
/// Apple embeds that hash in the signed token, and Supabase checks it against
/// the raw nonce we send with the token.
enum AppleNonce {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    /// `SystemRandomNumberGenerator` is documented as cryptographically secure,
    /// so no `SecRandomCopyBytes` retry loop is needed.
    static func make(length: Int = 32) -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in
            charset[Int(rng.next(upperBound: UInt64(charset.count)))]
        })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
