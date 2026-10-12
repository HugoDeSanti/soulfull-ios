//
//  MemberNameDecisionTests.swift
//  SoulfullTests
//
//  The name Home greets a member by. The profile's name wins; a profile that
//  lost its name gets the best one still known back (the phone's, then the
//  one given at sign-up); with no name anywhere nothing is invented.
//

import Testing
@testable import SoulfullGatherings

@Suite("The member's name")
struct MemberNameDecisionTests {

    let hugo = MemberName(first: "Hugo", last: "Santi")

    @Test func thePhoneTakesTheProfilesName() {
        let decision = MemberNameDecision(profile: hugo, device: MemberName(), signUp: MemberName())

        #expect(decision == .adopt(hugo))
    }

    @Test func theProfileWinsOverAnOlderNameOnThePhone() {
        let decision = MemberNameDecision(profile: hugo, device: MemberName(first: "Hugo"),
                                          signUp: MemberName(first: "H"))

        #expect(decision == .adopt(hugo))
    }

    @Test(arguments: [MemberName(first: "Hugo", last: "Santi"), MemberName(first: " Hugo", last: "Santi  ")])
    func theSameNameChangesNothing(onProfile: MemberName) {
        let decision = MemberNameDecision(profile: onProfile, device: hugo, signUp: MemberName())

        #expect(decision == .keep)
    }

    /// The wiped row this fixes: onboarding pushed an empty name, and the
    /// phone's copy was empty after a reinstall.
    @Test func aWipedProfileGetsTheSignUpNameBack() {
        let decision = MemberNameDecision(profile: MemberName(), device: MemberName(),
                                          signUp: MemberName(first: " Hugo", last: "Santi "))

        #expect(decision == .restore(hugo))
    }

    @Test func aWipedProfileTakesThePhonesNameBeforeTheSignUpName() {
        let decision = MemberNameDecision(profile: MemberName(first: "  "), device: hugo,
                                          signUp: MemberName(first: "Hugo"))

        #expect(decision == .restore(hugo))
    }

    /// An Apple account that shared no name: they aren't asked for one, and
    /// Home says "Friend".
    @Test func withNoNameAnywhereNothingIsInvented() {
        let decision = MemberNameDecision(profile: MemberName(), device: MemberName(first: " "),
                                          signUp: MemberName())

        #expect(decision == .keep)
    }
}
