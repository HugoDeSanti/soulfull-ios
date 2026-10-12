//
//  ConfirmationReadDecisionTests.swift
//  SoulfullTests
//
//  `refreshConfirmationState` re-reads the user to notice an email confirmed on
//  another device. The read answers for the session it was asked with, and a
//  sign-in can land while it's out: applying that late answer put the guest
//  back over the member who had just signed in.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Confirmation read")
struct ConfirmationReadDecisionTests {

    let guest = UUID()
    let member = UUID()

    /// A guest upgraded in place keeps their id: the ordinary confirmation.
    @Test func anAnswerForTheSameSessionApplies() {
        #expect(ConfirmationReadDecision.applies(answeredFor: guest, askedAs: guest, now: guest))
    }

    @Test func anAnswerForAGuestASignInHasReplacedIsIgnored() {
        #expect(!ConfirmationReadDecision.applies(answeredFor: guest, askedAs: guest, now: member))
    }

    @Test func anAnswerAfterTheSessionWentIsIgnored() {
        #expect(!ConfirmationReadDecision.applies(answeredFor: guest, askedAs: guest, now: nil))
    }

    /// Asked as one session and back with another is a change too, however
    /// it lines up.
    @Test func aReadThatStraddledAChangeIsIgnored() {
        #expect(!ConfirmationReadDecision.applies(answeredFor: member, askedAs: guest, now: member))
    }
}
