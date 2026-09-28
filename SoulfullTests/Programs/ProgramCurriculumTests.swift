//
//  ProgramCurriculumTests.swift
//  SoulfullTests
//
//  `programs.curriculum` is hand-authored jsonb. The row decode fails soft, so
//  a broken document looks exactly like an unauthored one on screen — these
//  pin down what the decoder forgives and what it keeps. `ProgramRow` decodes
//  it with a plain `JSONDecoder` (the types spell their own snake_case keys),
//  which is what these use too.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Program curriculum decoding")
struct ProgramCurriculumTests {

    func decode(_ json: String) throws -> ProgramCurriculum {
        try JSONDecoder().decode(ProgramCurriculum.self, from: Data(json.utf8))
    }

    /// The unlock rule walks days in order; an out-of-order document would
    /// otherwise gate the wrong day.
    @Test func daysAreSortedWhateverOrderTheyWereAuthoredIn() throws {
        let curriculum = try decode("""
            {"days": [
              {"day": 3, "title": "Letting go", "activities": []},
              {"day": 1, "title": "Arriving", "activities": []},
              {"day": 2, "title": "Steadiness", "activities": []}
            ]}
            """)

        #expect(curriculum.days.map(\.day) == [1, 2, 3])
    }

    /// One typo costs one activity, not the program.
    @Test func anUnreadableActivityIsSkippedAndTheRestOfTheDayKept() throws {
        let curriculum = try decode("""
            {"days": [{"day": 1, "title": "Arriving", "activities": [
              {"kind": "journal", "content_id": 1},
              {"kind": "massage", "content_id": 2},
              {"kind": "session"},
              {"kind": "recipe", "content_id": 3, "note": "Slowly."}
            ]}]}
            """)

        let activities = try #require(curriculum.days.first).activities
        #expect(activities.map(\.id) == ["journal-1", "recipe-3"])
        #expect(activities.last?.note == "Slowly.")
    }

    @Test func everyAuthoredFieldIsRead() throws {
        let curriculum = try decode("""
            {"overview": "A week of returns.",
             "closing": {"title": "You came back", "body": "That is the practice."},
             "days": [{"day": 1, "title": "Arriving", "intention": "Land first.",
                       "image_url": "retreat-images/dolomites-2027-09.jpg",
                       "activities": [{"kind": "exercise", "content_id": 4}]}]}
            """)

        let day = try #require(curriculum.days.first)
        #expect(curriculum.overview == "A week of returns.")
        #expect(curriculum.closing == ProgramClosing(title: "You came back", body: "That is the practice."))
        #expect(day.intention == "Land first.")
        #expect(day.imageUrl == "retreat-images/dolomites-2027-09.jpg")
        #expect(day.activities == [ProgramActivity(kind: .exercise, contentID: 4)])
    }

    @Test func aProgramWithNoAuthoredDaysCannotBeStarted() throws {
        let empty = try decode("{}")
        let authored = try decode(#"{"days": [{"day": 1, "title": "Arriving", "activities": []}]}"#)

        #expect(program(empty).isStartable == false)
        #expect(program(authored).isStartable)
        #expect(program(nil).isStartable == false)
    }

    private func program(_ curriculum: ProgramCurriculum?) -> Program {
        Program(id: "finding-ground", title: "Finding Ground", lead: "Alma Guerra", days: 7,
                imageUrl: "", curriculum: curriculum)
    }
}
