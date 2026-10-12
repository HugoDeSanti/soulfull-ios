//
//  RetreatEnquiryDateOfBirthTests.swift
//  SoulfullTests
//
//  The date-of-birth wheel on the retreat application opens on a plausible
//  date, but only turning it answers the question. Opening it used to write
//  that starting date into the answer, so a glance counted as a birthday and
//  the team was sent one nobody had chosen. The rest of the form's rules are
//  RetreatEnquiryFormTests.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Retreat application · date of birth")
struct RetreatEnquiryDateOfBirthTests {

    func form() -> RetreatEnquiryViewModel {
        RetreatEnquiryViewModel(retreat: Fixtures.retreat(), name: MemberName(first: "Mara"), accountEmail: "mara@example.com")
    }

    @Test func theWheelOpensOnItsStartingDateWithoutAnsweringTheQuestion() {
        let vm = form()

        let shown = vm.dateOfBirthWheel

        #expect(shown == RetreatEnquiryViewModel.defaultDateOfBirth)
        #expect(vm.dateOfBirth == nil)
        #expect(vm.missingAnswers.contains(RetreatEnquiry.Question.dateOfBirth))
        #expect(!vm.hasContent, "Looking at the wheel is not something to lose")
    }

    @Test func turningTheWheelAnswersTheQuestion() {
        let vm = form()
        let picked = Calendar.gregorian(in: "Europe/Madrid").at(1990, 5, 1, 12)

        vm.dateOfBirthWheel = picked

        #expect(vm.dateOfBirth == picked)
        #expect(!vm.missingAnswers.contains(RetreatEnquiry.Question.dateOfBirth))
        #expect(vm.hasContent)
    }
}
