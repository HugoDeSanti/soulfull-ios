//
//  MemberNameLimitTests.swift
//  SoulfullTests
//
//  A name is at most 64 characters, counted as Postgres's `char_length`
//  counts them (code points), so a name the app lets through is never refused
//  or cut differently by `profiles_full_name_length` (0030). The server trims
//  and cuts too; this is what the person sees while typing.
//

import Testing
@testable import SoulfullGatherings

@Suite("Member name limit")
struct MemberNameLimitTests {

    @Test func aNameWithinTheLimitIsKept() {
        #expect(MemberName.capped("Hugo De Santiago") == "Hugo De Santiago")
    }

    @Test func aLongerNameIsCutAtSixtyFour() {
        let typed = String(repeating: "a", count: 70)

        #expect(MemberName.capped(typed) == String(repeating: "a", count: 64))
    }

    /// "é" typed as e + a combining accent is one character and two code
    /// points; Postgres counts two.
    @Test func theLimitCountsCodePointsAsPostgresDoes() {
        let typed = String(repeating: "e\u{301}", count: 40)

        let cut = MemberName.capped(typed)

        #expect(cut.unicodeScalars.count == 64)
        #expect(cut.count == 32)
    }

    @Test func aCharacterIsNeverSplit() {
        let family = "👨‍👩‍👧"    // one character, five code points
        let typed = String(repeating: "a", count: 62) + family

        #expect(MemberName.capped(typed) == String(repeating: "a", count: 62))
    }

    @Test func typingKeepsTheSpaceBeforeTheNextWord() {
        #expect(MemberName.capped("Hugo ") == "Hugo ")
    }

    @Test(arguments: [
        ("  Hugo  ", "Hugo"),
        (String(repeating: "a", count: 63) + "  b", String(repeating: "a", count: 63)),
        ("   ", ""),
    ])
    func whatIsStoredIsTrimmedAndCut(typed: String, stored: String) {
        #expect(MemberName.limited(typed) == stored)
    }

    @MainActor @Test func theOnboardingNameFieldStopsAtTheLimit() {
        let vm = OnboardingViewModel()

        vm.name = String(repeating: "a", count: 70)

        #expect(vm.name.count == 64)
    }

    @MainActor @Test func theAccountNameFieldStopsAtTheLimit() {
        let vm = AccountViewModel()

        vm.fullName = String(repeating: "a", count: 70)

        #expect(vm.fullName.count == 64)
    }
}
