//
//  InstructorLibraryTests.swift
//  SoulfullTests
//
//  A guide's library includes the written practices that name them on their
//  own row (`instructor_id`, 0022), taken from the written libraries in each
//  library's order — the team's order, not the guide's. Another guide's
//  practices never leak in, and a guide known only for written practices has
//  a library, not an empty page.
//

import Testing
@testable import SoulfullGatherings

@Suite("Instructor library")
struct InstructorLibraryTests {

    /// The team's order is deliberately not id order. Alma made sequences 4
    /// and 1, recipe 2 and prompt 5; Mara made sequence 3; the rest name no
    /// guide.
    private let written = WrittenLibrary(
        journals: [Fixtures.journal(1), Fixtures.journal(5, guide: "alma-guerra")],
        exercises: [Fixtures.exercise(4, guide: "alma-guerra"), Fixtures.exercise(2),
                    Fixtures.exercise(1, guide: "alma-guerra"), Fixtures.exercise(3, guide: "mara-sole")],
        recipes: [Fixtures.recipe(1), Fixtures.recipe(2, guide: "alma-guerra")])

    private func libraryOf(_ id: String) -> InstructorLibrary {
        InstructorLibrary(programs: [], sessions: [], written: written, instructorID: id)
    }

    @Test func aGuidesWrittenPracticesAreTheOnesThatNameThem() {
        let alma = libraryOf("alma-guerra")

        #expect(alma.exercises.map(\.id) == [4, 1], "Library order, not id order")
        #expect(alma.recipes.map(\.id) == [2])
        #expect(alma.journals.map(\.id) == [5])
        #expect(alma.count == 4)
    }

    @Test func anotherGuidesPracticesAreLeftOut() {
        let mara = libraryOf("mara-sole")

        #expect(mara.exercises.map(\.id) == [3])
        #expect(mara.recipes.isEmpty)
        #expect(mara.journals.isEmpty)
    }

    @Test func aGuideWithOnlyWrittenPracticesIsNotEmpty() {
        #expect(!libraryOf("mara-sole").isEmpty)
    }

    @Test func aGuideWhoMadeNothingHasAnEmptyLibrary() {
        #expect(libraryOf("noa-castell").isEmpty)
    }
}
