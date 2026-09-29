//
//  InstructorLibraryTests.swift
//  SoulfullTests
//
//  A guide's library includes the written practices credited to them in
//  `practice_credits`, resolved against the written libraries as read from
//  their tables. A credit and its practice are separate rows, so a credit for
//  a practice that isn't published must cost that line, not the page; and
//  sessions are credited on their own row, never through a credit.
//

import Testing
@testable import SoulfullGatherings

@Suite("Instructor library")
struct InstructorLibraryTests {

    private func credit(_ kind: PracticeContentKind, _ id: Int) -> PracticeCredit {
        PracticeCredit(kind: kind, contentID: id, instructorID: "alma-guerra")
    }

    /// The live libraries' shape: five prompts, five sequences, three recipes.
    private let written = Fixtures.library(journals: [1, 2, 3, 4, 5], exercises: [1, 2, 3, 4, 5], recipes: [1, 2, 3])

    private func resolve(_ credits: [PracticeCredit]) -> InstructorLibrary {
        InstructorLibrary(programs: [], sessions: [], credits: credits, library: written)
    }

    @Test func creditedPracticesAreResolvedFromTheirLibraries() {
        let library = resolve([credit(.exercise, 4), credit(.recipe, 1), credit(.journal, 2)])

        #expect(library.exercises.map(\.id) == [4])
        #expect(library.recipes.map(\.id) == [1])
        #expect(library.journals.map(\.id) == [2])
        #expect(library.count == 3)
    }

    @Test func theyKeepTheLibrarysOwnOrderNotTheCreditsOrder() {
        let library = resolve([credit(.exercise, 5), credit(.exercise, 1), credit(.exercise, 3)])

        #expect(library.exercises.map(\.id) == [1, 3, 5])
    }

    @Test func aCreditForAPracticeTheLibraryDoesntHoldIsDropped() {
        let library = resolve([credit(.recipe, 999), credit(.recipe, 2)])

        #expect(library.recipes.map(\.id) == [2])
    }

    @Test func aSessionCreditIsIgnoredBecauseSessionsCarryTheirOwnGuide() {
        let library = resolve([credit(.session, 1)])

        #expect(library.isEmpty)
    }

    @Test func aGuideWithOnlyWrittenPracticesIsNotEmpty() {
        let library = resolve([credit(.journal, 1)])

        #expect(!library.isEmpty)
    }

    @Test func theKeyMatchesTheShapeProgressAndPresenceUse() {
        #expect(credit(.exercise, 4).key == "exercise-4")
    }
}
