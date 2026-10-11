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

    @Test func thePhoneTakesTheProfilesName() {
        let decision = MemberNameDecision(profile: "Hugo Santi", device: "", signUp: "")

        #expect(decision == .adopt("Hugo Santi"))
    }

    @Test func theProfileWinsOverAnOlderNameOnThePhone() {
        let decision = MemberNameDecision(profile: "Hugo Santi", device: "Hugo", signUp: "H")

        #expect(decision == .adopt("Hugo Santi"))
    }

    @Test(arguments: ["Hugo Santi", " Hugo Santi  "])
    func theSameNameChangesNothing(onProfile: String) {
        let decision = MemberNameDecision(profile: onProfile, device: "Hugo Santi", signUp: "")

        #expect(decision == .keep)
    }

    /// The wiped row this fixes: onboarding pushed an empty name, and the
    /// phone's copy was empty after a reinstall.
    @Test func aWipedProfileGetsTheSignUpNameBack() {
        let decision = MemberNameDecision(profile: "", device: "", signUp: " Hugo Santi ")

        #expect(decision == .restore("Hugo Santi"))
    }

    @Test func aWipedProfileTakesThePhonesNameBeforeTheSignUpName() {
        let decision = MemberNameDecision(profile: "  ", device: "Hugo Santi", signUp: "Hugo")

        #expect(decision == .restore("Hugo Santi"))
    }

    /// An Apple account that shared no name: they aren't asked for one, and
    /// Home says "Friend".
    @Test func withNoNameAnywhereNothingIsInvented() {
        let decision = MemberNameDecision(profile: "", device: " ", signUp: "")

        #expect(decision == .keep)
    }
}
