//
//  AuthFailureCopyTests.swift
//  SoulfullTests
//
//  What the account sheet says when an auth call fails. It separates only
//  what is equally true of every address (no connection, too many attempts,
//  trouble at our end) and otherwise says the same thing whatever the server
//  said, so the banner can't be used to find out who has an account.
//

import AuthenticationServices
import Foundation
import Testing
@preconcurrency import Supabase
@testable import SoulfullGatherings

/// A GoTrue error response, shaped the way the SDK throws it.
private func goTrue(_ status: Int, _ code: ErrorCode) -> AuthError {
    .api(message: "", errorCode: code, underlyingData: Data(),
         underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.supabase.co/auth/v1/signup")!,
                                             statusCode: status, httpVersion: nil, headerFields: nil)!)
}

@Suite("Auth failure copy")
struct AuthFailureCopyTests {

    /// Offline used to read as wrong credentials.
    @Test(arguments: [AuthFailureCopy.Action.createAccount, .signIn, .confirmCode, .resendCode, .apple,
                      .requestReset, .newPassword])
    func beingOfflineSaysSoWhateverWasTried(action: AuthFailureCopy.Action) {
        let message = AuthFailureCopy.message(for: URLError(.notConnectedToInternet), during: action)

        #expect(message == AuthFailureCopy.offline)
    }

    @Test(arguments: [
        goTrue(429, .overRequestRateLimit),
        goTrue(429, .overEmailSendRateLimit),
        goTrue(429, .unknown),
    ])
    func aRateLimitSaysToWaitAMinute(error: AuthError) {
        #expect(AuthFailureCopy.message(for: error, during: .resendCode) == AuthFailureCopy.rateLimited)
    }

    @Test(arguments: [
        goTrue(500, .unexpectedFailure) as any Error,
        goTrue(502, .unknown),
        URLError(.timedOut),
        URLError(.cannotConnectToHost),
    ])
    func troubleAtOurEndIsntBlamedOnTheirPassword(error: any Error) {
        #expect(AuthFailureCopy.message(for: error, during: .signIn) == AuthFailureCopy.unreachable)
    }

    /// GoTrue tells "already registered" from a fresh address; the banner
    /// must not.
    @Test func creatingAnAccountSaysTheSameWhetherOrNotTheAddressIsTaken() {
        let taken = AuthFailureCopy.message(for: goTrue(422, .emailExists), during: .createAccount)
        let alsoTaken = AuthFailureCopy.message(for: goTrue(422, .userAlreadyExists), during: .createAccount)
        let invalid = AuthFailureCopy.message(for: goTrue(400, .validationFailed), during: .createAccount)

        #expect(taken == alsoTaken)
        #expect(taken == invalid)
    }

    @Test func signingInSaysTheSameWhetherTheAccountExistsOrNot() {
        let wrongPassword = AuthFailureCopy.message(for: goTrue(400, .invalidCredentials), during: .signIn)
        let unconfirmed = AuthFailureCopy.message(for: goTrue(400, .emailNotConfirmed), during: .signIn)

        #expect(wrongPassword == unconfirmed)
    }

    /// Only someone who has just proved the address is theirs is choosing a
    /// new password, so a weak one can be named as the problem.
    @Test func aWeakNewPasswordSaysSoAndOtherRefusalsDont() {
        let weak = AuthFailureCopy.message(for: AuthError.weakPassword(message: "", reasons: ["length"]),
                                           during: .newPassword)
        let other = AuthFailureCopy.message(for: goTrue(400, .validationFailed), during: .newPassword)

        #expect(weak.contains("stronger"))
        #expect(weak != other)
    }

    @Test func thePasswordTheyAlreadyHaveIsToldApart() {
        #expect(AuthFailureCopy.isSamePassword(goTrue(422, .samePassword)))
        #expect(!AuthFailureCopy.isSamePassword(goTrue(422, .weakPassword)))
        #expect(!AuthFailureCopy.isSamePassword(URLError(.timedOut)))
    }

    /// The raw description was "The operation couldn't be completed.
    /// (com.apple.AuthenticationServices.AuthorizationError error 1000.)".
    @Test(arguments: [ASAuthorizationError.Code.unknown, .failed, .invalidResponse, .notHandled])
    func anAppleFailureGetsWordsNotAnErrorNumber(code: ASAuthorizationError.Code) {
        let message = AuthFailureCopy.message(for: ASAuthorizationError(code), during: .apple)

        #expect(message.hasPrefix("Sign in with Apple"))
        #expect(!message.contains("1000"))
    }

    @Test func backingOutOfAppleIsNotAFailure() {
        #expect(AuthFailureCopy.isUserCancellation(ASAuthorizationError(.canceled)))
        #expect(AuthFailureCopy.isUserCancellation(CancellationError()))
        #expect(AuthFailureCopy.isUserCancellation(URLError(.cancelled)))
        #expect(!AuthFailureCopy.isUserCancellation(ASAuthorizationError(.unknown)))
    }
}
