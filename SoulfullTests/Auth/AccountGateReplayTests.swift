//
//  AccountGateReplayTests.swift
//  SoulfullTests
//
//  Browsing is free; the account is asked for at the moment someone reaches
//  for something personal, and the tap they were making is replayed once the
//  account exists — never lost, never replayed for someone who backed out.
//  The sheet itself is covered end to end by SoulfullUITests/AccountGateTests.
//

import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Account gate replay")
struct AccountGateReplayTests {

    /// Counts how often the interrupted action ran.
    final class Tap {
        var count = 0
        func action() -> () -> Void { { self.count += 1 } }
    }

    @Test func aMemberIsNeverStopped() {
        let gate = AccountGate(), tap = Tap()

        let raiseSheet = gate.require(signedIn: true, tap.action())

        #expect(!raiseSheet)
        #expect(tap.count == 1)
    }

    @Test func aGuestIsAskedFirstAndTheTapWaits() {
        let gate = AccountGate(), tap = Tap()

        let raiseSheet = gate.require(signedIn: false, tap.action())

        #expect(raiseSheet)
        #expect(tap.count == 0)
    }

    @Test func signingInReplaysTheInterruptedTapExactlyOnce() {
        let gate = AccountGate(), tap = Tap()
        _ = gate.require(signedIn: false, tap.action())

        gate.resume(signedIn: true)
        gate.resume(signedIn: true)

        #expect(tap.count == 1)
    }

    @Test func backingOutDropsTheTapForGood() {
        let gate = AccountGate(), tap = Tap()
        _ = gate.require(signedIn: false, tap.action())

        gate.resume(signedIn: false)
        gate.resume(signedIn: true)

        #expect(tap.count == 0)
    }

    @Test func onlyTheLatestInterruptedTapIsReplayed() {
        let gate = AccountGate(), first = Tap(), second = Tap()
        _ = gate.require(signedIn: false, first.action())
        _ = gate.require(signedIn: false, second.action())

        gate.resume(signedIn: true)

        #expect(first.count == 0)
        #expect(second.count == 1)
    }
}
