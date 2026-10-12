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

/// Everything one Apple authorization gives us. Grouped rather than passed as
/// four positional parameters, because two of the four are optional strings and
/// transposing them at a call site would fail silently.
struct AppleCredential {
    /// The signed identity token Supabase exchanges for a session.
    let idToken: String
    /// Raw (un-hashed) nonce — Supabase needs it to verify the `nonce` claim
    /// Apple embedded in the signed token.
    let nonce: String
    /// Apple sends the name on the very first authorization only.
    let fullName: String?
    /// Single-use code, valid about five minutes, which the server exchanges
    /// for Apple's refresh token.
    ///
    /// That refresh token is the only way to call Apple's `/auth/revoke` when
    /// the member deletes their account — which App Store Guideline 5.1.1(v)
    /// requires of any app offering both Sign in with Apple and account
    /// deletion. Deleting the Supabase user does **not** revoke the grant: the
    /// app goes on appearing under Settings → Apple ID → Sign in with Apple
    /// until Apple is told, and that is what a reviewer checks.
    ///
    /// Optional only so that a missing code can never block a sign-in the
    /// member asked for. Apple issues a new one on every authorization, so the
    /// next sign-in repairs it.
    let authorizationCode: String?
}

struct AppleSignInButton: View {
    var disabled: Bool = false
    let onCredential: (AppleCredential) -> Void
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
        // Apple's button draws its own rounded fill, which can't be clipped
        // square from outside. White behind it fills the corners in, so it
        // reads as a square white block like the app's other buttons. Pure
        // white, not `Theme.ink`: the corners have to match Apple's fill.
        .background(Color.white)
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
        .animation(Theme.Motion.settle, value: disabled)
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
            let name = credential.fullName.map { MemberName.limited($0.formatted()) }
            // The code is opaque ASCII. Absent is survivable (see
            // `AppleCredential.authorizationCode`), so don't fail the sign-in.
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            onCredential(
                AppleCredential(idToken: token,
                                nonce: nonce,
                                fullName: (name?.isEmpty ?? true) ? nil : name,
                                authorizationCode: (code?.isEmpty ?? true) ? nil : code)
            )
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
    // Note the W: the widely-copied version of this line (Firebase's sample)
    // omits it, which is a typo rather than a constraint. 65 characters, and
    // `next(upperBound:)` is unbiased, so entropy is ~5.98 bits/char.
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

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
