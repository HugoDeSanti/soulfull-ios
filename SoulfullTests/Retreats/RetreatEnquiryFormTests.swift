//
//  RetreatEnquiryFormTests.swift
//  SoulfullTests
//
//  The retreat application — the only way to reach the retreat team from the
//  app while reservations are off. What makes an application complete, and
//  what goes over the wire to `send-retreat-enquiry`. That the form renders
//  and Submit settles is SoulfullUITests/RetreatEnquiryTests.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Retreat application")
struct RetreatEnquiryFormTests {

    func form(name: String = "") -> RetreatEnquiryViewModel {
        RetreatEnquiryViewModel(retreat: Fixtures.retreat(), name: name,
                                accountEmail: "mara@example.com")
    }

    /// Every required question answered, with the padding people type.
    func completedForm() -> RetreatEnquiryViewModel {
        let vm = form(name: "Mara")
        vm.lastName = "  Ortega "
        vm.dateOfBirth = Calendar.current.date(from: DateComponents(year: 1990, month: 5, day: 1, hour: 12))
        vm.basedIn = " Barcelona, Spain"
        vm.phone = "+34 600 000 000 "
        vm.about = "  I want a week that puts me back in my body.  "
        vm.decision = .readyToJoin
        vm.investment = .band4500
        return vm
    }

    // MARK: - Completeness

    @Test func anEmptyFormListsWhatIsMissingInTheOrderItAsks() {
        let vm = form()

        #expect(vm.missingAnswers == [
            "Name", "Date of Birth", "Where you're based", "Phone",
            "A little about you", "Where you are in your decision", "Your usual investment",
        ])
        #expect(!vm.canSubmit)
        #expect(vm.makeEnquiry() == nil)
    }

    @Test func whitespaceIsNotAnAnswer() {
        let vm = completedForm()
        vm.lastName = "   "
        vm.basedIn = "\n"
        vm.about = " "

        #expect(vm.missingAnswers == ["Name", "Where you're based", "A little about you"])
        #expect(vm.makeEnquiry() == nil)
    }

    /// Loose on purpose: numbers arrive with country codes, spaces, dashes and
    /// parentheses from a dozen countries.
    @Test(arguments: [
        ("+34 600 000 000", true),
        ("(555) 123-4567", true),
        ("1234567", true),
        ("123-456", false),
        ("call me", false),
    ])
    func aPhoneNumberNeedsSevenDigitsHoweverItIsWritten(phone: String, valid: Bool) {
        let vm = form()
        vm.phone = phone

        #expect(vm.isPhoneValid == valid)
    }

    @Test func aCompleteFormBuildsATrimmedApplicationWithTheOptionalAnswersBlank() throws {
        let enquiry = try #require(completedForm().makeEnquiry())

        #expect(enquiry.fullName == "Mara Ortega")
        #expect(enquiry.basedIn == "Barcelona, Spain")
        #expect(enquiry.phone == "+34 600 000 000")
        #expect(enquiry.about == "I want a week that puts me back in my body.")
        #expect(enquiry.retreat == Fixtures.retreat().enquiryLabel)
        #expect(enquiry.instagram.isEmpty)
        #expect(enquiry.referral.isEmpty)
    }

    /// Drives the discard guard: a form nobody touched closes without asking,
    /// even though onboarding's name was filled in for them.
    @Test func theNamePrefilledFromOnboardingIsNotSomethingToLose() {
        let untouched = form(name: "Mara")
        let renamed = form(name: "Mara")
        renamed.firstName = "Marina"
        let answered = form(name: "Mara")
        answered.basedIn = "Lisbon"

        #expect(untouched.firstName == "Mara")
        #expect(!untouched.hasContent)
        #expect(renamed.hasContent)
        #expect(answered.hasContent)
    }

    // MARK: - Wire format

    @Test func theBodyUsesTheFunctionsKeysAndTheTeamsOwnAnswerLabels() throws {
        let vm = completedForm()
        vm.investment = .band3500
        let enquiry = try #require(vm.makeEnquiry())

        let body = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(enquiry)) as? [String: String])

        #expect(Set(body.keys) == ["first_name", "last_name", "date_of_birth", "based_in", "phone",
                                   "instagram", "retreat", "about", "decision", "investment", "referral"])
        #expect(body["date_of_birth"] == "1990-05-01")
        #expect(body["decision"] == "I'm completely ready to join")
        #expect(body["investment"] == "€3500+")
        #expect(body["email"] == nil, "The server reads the address from the JWT, never the body")
    }

    /// Regression: the date was formatted in UTC while the form showed it in
    /// the device's zone, and the picker keeps the time of day it opened at —
    /// so an evening in New York or a morning in Tokyo sent the team the day
    /// either side of the one on screen.
    @Test(arguments: [
        ("America/New_York", 21),
        ("America/Los_Angeles", 23),
        ("Asia/Tokyo", 8),
        ("Pacific/Auckland", 7),
        ("Europe/Madrid", 0),
    ])
    func theDateOfBirthSentIsTheDayThatWasPicked(zone: String, hour: Int) {
        let calendar = Calendar.gregorian(in: zone)
        let picked = calendar.at(1990, 5, 1, hour)

        #expect(RetreatEnquiry.dayString(picked, in: calendar.timeZone) == "1990-05-01")
    }
}
