//
//  InstructorLibraryTests.swift
//  SoulfullTests
//
//  A guide's library includes the written practices credited to them in
//  `practice_credits`, resolved against the libraries this build carries. The
//  credits are data and can run ahead of a release, so a credit for something
//  the build doesn't have must cost that line, not the page; and sessions are
//  credited on their own row, never through a credit.
//

import Testing
@testable import SoulfullGatherings

@Suite("Instructor library")
struct InstructorLibraryTests {

    private func credit(_ kind: PracticeContentKind, _ id: Int) -> PracticeCredit {
        PracticeCredit(kind: kind, contentID: id, instructorID: "alma-guerra")
    }

    @Test func creditedPracticesAreResolvedFromTheirLibraries() {
        let library = InstructorLibrary(programs: [], sessions: [],
                                        credits: [credit(.exercise, 4), credit(.recipe, 1), credit(.journal, 2)])

        #expect(library.exercises.map(\.id) == [4])
        #expect(library.recipes.map(\.id) == [1])
        #expect(library.journals.map(\.id) == [2])
        #expect(library.count == 3)
    }

    @Test func theyKeepTheLibrarysOwnOrderNotTheCreditsOrder() {
        let library = InstructorLibrary(programs: [], sessions: [],
                                        credits: [credit(.exercise, 5), credit(.exercise, 1), credit(.exercise, 3)])

        #expect(library.exercises.map(\.id) == [1, 3, 5])
    }

    @Test func aCreditForSomethingThisBuildLacksIsDropped() {
        let library = InstructorLibrary(programs: [], sessions: [],
                                        credits: [credit(.recipe, 999), credit(.recipe, 2)])

        #expect(library.recipes.map(\.id) == [2])
    }

    @Test func aSessionCreditIsIgnoredBecauseSessionsCarryTheirOwnGuide() {
        let library = InstructorLibrary(programs: [], sessions: [], credits: [credit(.session, 1)])

        #expect(library.isEmpty)
    }

    @Test func aGuideWithOnlyWrittenPracticesIsNotEmpty() {
        let library = InstructorLibrary(programs: [], sessions: [], credits: [credit(.journal, 1)])

        #expect(!library.isEmpty)
    }

    @Test func theKeyMatchesTheShapeProgressAndPresenceUse() {
        #expect(credit(.exercise, 4).key == "exercise-4")
    }
}
