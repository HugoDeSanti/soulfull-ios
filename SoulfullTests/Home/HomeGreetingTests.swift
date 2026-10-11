//
//  HomeGreetingTests.swift
//  SoulfullTests
//
//  Home greets a member by their first name alone, and says "Friend" when
//  there is no name (an Apple account that shared none).
//

import Testing
@testable import SoulfullGatherings

@Suite("Home · the greeting's name")
struct HomeGreetingTests {

    @Test(arguments: [
        ("Hugo Santi", "Hugo"),
        ("María José García", "María"),
        ("  Mara   Lopez ", "Mara"),
        ("Mara", "Mara"),
    ])
    func greetsByTheFirstNameAlone(fullName: String, greeted: String) {
        #expect(HomeViewModel.greetingName(fullName) == greeted)
    }

    @Test(arguments: ["", "   "])
    func withNoNameItSaysFriend(fullName: String) {
        #expect(HomeViewModel.greetingName(fullName) == "Friend")
    }
}
