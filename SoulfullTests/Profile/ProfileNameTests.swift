//
//  ProfileNameTests.swift
//  SoulfullTests
//
//  The phone's copy of the member's name follows the account's. A member's
//  name lives on their profile, and a guide linked to the account is named
//  from it (0027), so a phone that kept showing an older name put one name on
//  the You tab and another on the guide page. An empty name on the server
//  never blanks the phone's.
//

import Testing
@testable import SoulfullGatherings

@Suite("You tab · the account's name")
struct ProfileNameTests {

    @Test func aNameChangedOnTheServerReachesThePhone() {
        let adopted = ProfileViewModel.adoptedName(server: "Hugo Santi", device: "michy Bitchy")

        #expect(adopted == "Hugo Santi")
    }

    @Test func anEmptyServerNameLeavesThePhonesName() {
        #expect(ProfileViewModel.adoptedName(server: "", device: "Hugo") == nil)
        #expect(ProfileViewModel.adoptedName(server: "   ", device: "Hugo") == nil)
    }

    @Test func theSameNameChangesNothing() {
        let adopted = ProfileViewModel.adoptedName(server: "Hugo Santi", device: "Hugo Santi")

        #expect(adopted == nil)
    }

    @Test func surroundingSpacesAreNotPartOfTheName() {
        let adopted = ProfileViewModel.adoptedName(server: "  Hugo Santi ", device: "Hugo Santi")

        #expect(adopted == nil)
    }
}
