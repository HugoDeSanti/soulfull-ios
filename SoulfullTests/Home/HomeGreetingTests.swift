//
//  HomeGreetingTests.swift
//  SoulfullTests
//
//  Home greets a member by their first name, all of it, and says "Friend"
//  when there is no name (an Apple account that shared none).
//

import Testing
@testable import SoulfullGatherings

@Suite("Home · the greeting's name")
struct HomeGreetingTests {

    @Test(arguments: [
        (MemberName(first: "Hugo", last: "Santi"), "Hugo"),
        (MemberName(first: "María José", last: "García"), "María José"),
        (MemberName(first: "  Mara ", last: " Lopez"), "Mara"),
        (MemberName(first: "Mara"), "Mara"),
    ])
    func greetsByTheFirstName(name: MemberName, greeted: String) {
        #expect(HomeViewModel.greetingName(name) == greeted)
    }

    @Test(arguments: [MemberName(), MemberName(first: "   ", last: " ")])
    func withNoNameItSaysFriend(name: MemberName) {
        #expect(HomeViewModel.greetingName(name) == "Friend")
    }
}
