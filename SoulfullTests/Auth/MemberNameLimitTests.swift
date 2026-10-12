//
//  MemberNameLimitTests.swift
//  SoulfullTests
//
//  A name is at most 64 characters, counted as Postgres's `char_length`
//  counts them (code points), so a name the app lets through is never refused
//  or cut differently by `profiles_full_name_length` (0030). The server trims
//  and cuts too; this is what the person sees while typing. The two parts
//  share the 64 the way 0033 cuts them: the first name first, then what's
//  left of the last.
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

    @MainActor @Test func theAccountNameFieldsStopAtTheLimit() {
        let vm = AccountViewModel()

        vm.firstName = String(repeating: "a", count: 70)
        vm.lastName = String(repeating: "b", count: 70)

        #expect(vm.firstName.count == 64)
        #expect(vm.lastName.count == 64)
    }

    // MARK: - Two parts, one limit

    @Test func theLastNameGetsWhatTheFirstLeaves() {
        let name = MemberName(first: String(repeating: "a", count: 40),
                              last: String(repeating: "b", count: 40))

        let stored = name.limited

        #expect(stored.first == String(repeating: "a", count: 40))
        #expect(stored.last == String(repeating: "b", count: 23))
        #expect(stored.full.unicodeScalars.count == 64)
    }

    @Test func aFirstNameAtTheLimitLeavesNoRoomForALastName() {
        let name = MemberName(first: String(repeating: "a", count: 64), last: "Lopez")

        #expect(name.limited == MemberName(first: String(repeating: "a", count: 64)))
    }

    @Test func eachPartIsTrimmed() {
        let name = MemberName(first: "  Mary Ann ", last: "\tSmith  ")

        #expect(name.limited == MemberName(first: "Mary Ann", last: "Smith"))
        #expect(name.full == "Mary Ann Smith")
    }

    /// As the server does: a last name alone is the name they go by.
    @Test func aLastNameAloneBecomesTheFirst() {
        #expect(MemberName(first: " ", last: "Lopez").limited == MemberName(first: "Lopez"))
    }

    // MARK: - A name on one line

    /// The phone's copy from before the parts, and an older build's sign-up,
    /// split as 0033 split the names already stored.
    @Test(arguments: [
        ("Hugo De Santiago", MemberName(first: "Hugo", last: "De Santiago")),
        ("  Mara   Lopez ", MemberName(first: "Mara", last: "Lopez")),
        ("Mara", MemberName(first: "Mara")),
        ("   ", MemberName()),
    ])
    func aLineIsSplitAtTheFirstSpace(line: String, name: MemberName) {
        #expect(MemberName(line: line) == name)
    }

    // MARK: - Sign-up metadata

    @Test func theSignUpMetadataCarriesBothPartsAndTheLine() {
        let metadata = AuthManager.signUpMetadata(name: MemberName(first: " Mary Ann", last: "Smith "))

        #expect(metadata?["first_name"]?.stringValue == "Mary Ann")
        #expect(metadata?["last_name"]?.stringValue == "Smith")
        #expect(metadata?["full_name"]?.stringValue == "Mary Ann Smith")
    }

    @Test func noNameSendsNoMetadata() {
        #expect(AuthManager.signUpMetadata(name: MemberName(first: " ")) == nil)
    }

    @Test func theSignUpNameIsReadFromItsPartsOrAnOlderBuildsLine() {
        let parts = AuthManager.signUpName(["first_name": .string("Mary Ann"), "last_name": .string("Smith"),
                                            "full_name": .string("Mary Ann Smith")])
        let line = AuthManager.signUpName(["full_name": .string("Hugo De Santiago")])

        #expect(parts == MemberName(first: "Mary Ann", last: "Smith"))
        #expect(line == MemberName(first: "Hugo", last: "De Santiago"))
    }

    /// Apple's name, the one time it's shared, fills only what the phone
    /// doesn't know: onboarding asked for the first name.
    @Test func applesNameFillsOnlyTheMissingParts() {
        let onboarded = MemberName(first: "Huguito")
        let apple = MemberName(first: "Hugo", last: "De Santiago")

        #expect(onboarded.filled(from: apple) == MemberName(first: "Huguito", last: "De Santiago"))
        #expect(MemberName().filled(from: apple) == apple)
    }
}
