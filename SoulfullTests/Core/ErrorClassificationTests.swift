//
//  ErrorClassificationTests.swift
//  SoulfullTests
//
//  Every load failure in the app says either "you're offline" or "something
//  went wrong at our end", and cancellation says nothing at all. Telling
//  someone on a train to "try again" is useless; telling someone whose
//  connection is fine to "check your connection" sends them after the wrong
//  problem. `Error.isOffline` is deliberately conservative.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Error classification")
struct ErrorClassificationTests {

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, true),
        (.networkConnectionLost, true),
        (.dataNotAllowed, true),
        (.internationalRoamingOff, true),
        // As likely to mean our backend is down as that the device is offline.
        (.timedOut, false),
        (.cannotConnectToHost, false),
        (.badServerResponse, false),
    ])
    func onlyAMissingConnectionCountsAsOffline(code: URLError.Code, offline: Bool) {
        #expect(URLError(code).isOffline == offline)
    }

    /// The Supabase SDK hands some failures back already bridged to NSError.
    @Test func aBridgedErrorIsReadByItsDomainAndCode() {
        let bridged = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let elsewhere = NSError(domain: "PostgREST", code: NSURLErrorNotConnectedToInternet)

        #expect(bridged.isOffline)
        #expect(!elsewhere.isOffline)
    }

    /// A stream that loses its connection fails with AVFoundation's own error,
    /// the URL error underneath it. The player has to read through to say
    /// "you're offline" rather than "our end".
    @Test func aWrappedErrorIsReadByWhatItWraps() {
        func wrapping(_ code: Int) -> NSError {
            NSError(domain: "AVFoundationErrorDomain", code: -11800,
                    userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: code)])
        }

        #expect(wrapping(NSURLErrorNotConnectedToInternet).isOffline)
        #expect(!wrapping(NSURLErrorTimedOut).isOffline)
        #expect(!NSError(domain: "AVFoundationErrorDomain", code: -11800).isOffline)
    }

    /// The SDK surfaces a cancelled task as `URLError(.cancelled)`, not
    /// `CancellationError` — both must read as cancellation, nothing else must.
    @Test func cancellationArrivesInTwoShapes() {
        #expect(CancellationError().isCancellation)
        #expect(URLError(.cancelled).isCancellation)
        #expect(!URLError(.timedOut).isCancellation)
        #expect(!AppError.unknown.isCancellation)
    }
}
