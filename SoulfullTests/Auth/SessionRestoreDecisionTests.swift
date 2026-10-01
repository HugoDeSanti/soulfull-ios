//
//  SessionRestoreDecisionTests.swift
//  SoulfullTests
//
//  What a failed session restore at launch does to the session stored on the
//  device. Only a session that is really gone may be replaced by a fresh
//  guest: a first launch, a purged guest, a refresh token the server refused.
//  Anything that only stopped us *checking* it (offline, a timeout, our
//  backend erroring) keeps it for Retry. Getting this wrong the old way
//  signed members out on a two-second network glitch.
//

import Foundation
import Testing
@preconcurrency import Supabase
@testable import SoulfullGatherings

/// A GoTrue error response, shaped the way the SDK throws it.
private func goTrue(_ status: Int, _ code: ErrorCode) -> AuthError {
    .api(message: "", errorCode: code, underlyingData: Data(),
         underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.supabase.co/auth/v1/token")!,
                                             statusCode: status, httpVersion: nil, headerFields: nil)!)
}

@Suite("Session restore at launch")
struct SessionRestoreDecisionTests {

    /// The SDK throws this when nothing is stored (a first launch), and also
    /// after it deleted a session whose refresh token was refused, which is
    /// how a guest purged by the nightly job arrives.
    @Test func noStoredSessionOpensAGuest() {
        let decision = SessionRestoreDecision(after: AuthError.sessionMissing)

        #expect(decision == .openGuest)
    }

    @Test(arguments: [
        goTrue(400, .refreshTokenNotFound),
        goTrue(400, .refreshTokenAlreadyUsed),
        goTrue(400, .sessionNotFound),
        goTrue(403, .userNotFound),
        // The OAuth-shaped refusal (`"error": "invalid_grant"`) carries no
        // code; its status is the evidence.
        goTrue(400, .unknown),
        goTrue(401, .badJWT),
    ])
    func aRefreshTokenTheServerRefusedOpensAGuest(error: AuthError) {
        #expect(SessionRestoreDecision(after: error) == .openGuest)
    }

    @Test(arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .dataNotAllowed,
    ])
    func aRefreshThatNeverLeftTheDeviceKeepsTheSession(code: URLError.Code) {
        #expect(SessionRestoreDecision(after: URLError(code)) == .keepSession(.offline))
    }

    @Test(arguments: [
        URLError(.timedOut) as any Error,
        URLError(.cannotConnectToHost),
        goTrue(500, .unexpectedFailure),
        goTrue(503, .unknown),
        goTrue(504, .requestTimeout),
        // "Not now" rather than "never".
        goTrue(429, .overRequestRateLimit),
        goTrue(408, .requestTimeout),
    ])
    func troubleAtOurEndKeepsTheSession(error: any Error) {
        #expect(SessionRestoreDecision(after: error) == .keepSession(.unreachable))
    }

    /// `.unexpectedFailure` is the SDK's label for a body that isn't a GoTrue
    /// error at all, such as a hotel Wi-Fi login page or a proxy's 403. That
    /// status says nothing about the token.
    @Test func aRefusalThatIsntFromOurServerKeepsTheSession() {
        let decision = SessionRestoreDecision(after: goTrue(403, .unexpectedFailure))

        #expect(decision == .keepSession(.unreachable))
    }

    @Test func anErrorItDoesntRecogniseKeepsTheSession() {
        let decision = SessionRestoreDecision(after: AppError.unknown)

        #expect(decision == .keepSession(.unreachable))
    }
}
