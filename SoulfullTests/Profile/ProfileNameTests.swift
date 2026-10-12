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

    let hugo = MemberName(first: "Hugo", last: "Santi")

    @Test func aNameChangedOnTheServerReachesThePhone() {
        let adopted = ProfileViewModel.adoptedName(server: hugo, device: MemberName(first: "michy", last: "Bitchy"))

        #expect(adopted == hugo)
    }

    @Test func aLastNameAddedOnTheServerReachesThePhone() {
        let adopted = ProfileViewModel.adoptedName(server: hugo, device: MemberName(first: "Hugo"))

        #expect(adopted == hugo)
    }

    @Test func anEmptyServerNameLeavesThePhonesName() {
        #expect(ProfileViewModel.adoptedName(server: MemberName(), device: MemberName(first: "Hugo")) == nil)
        #expect(ProfileViewModel.adoptedName(server: MemberName(first: "   "), device: MemberName(first: "Hugo")) == nil)
    }

    @Test func theSameNameChangesNothing() {
        let adopted = ProfileViewModel.adoptedName(server: hugo, device: hugo)

        #expect(adopted == nil)
    }

    @Test func surroundingSpacesAreNotPartOfTheName() {
        let adopted = ProfileViewModel.adoptedName(server: MemberName(first: "  Hugo", last: "Santi "), device: hugo)

        #expect(adopted == nil)
    }
}
