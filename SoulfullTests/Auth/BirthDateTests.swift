//
//  BirthDateTests.swift
//  SoulfullTests
//
//  A member's date of birth is a calendar day: written as Postgres writes a
//  `date`, kept on the day the wheel showed wherever the phone is, and never
//  later than 13 years ago (the Terms' minimum age, which 0033 holds too).
//  It is asked with an email account, and only turning the wheel answers.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Date of birth")
struct BirthDateTests {

    @Test(arguments: ["1990-05-01", "2000-02-29", "1900-01-01"])
    func aDayRoundTripsAsPostgresWritesIt(_ day: String) {
        #expect(BirthDate(dayString: day)?.dayString == day)
    }

    @Test(arguments: ["1990-02-30", "2001-02-29", "1990-13-01", "soon", "1990-05", ""])
    func anythingButARealDayIsNotADate(_ day: String) {
        #expect(BirthDate(dayString: day) == nil)
    }

    /// 23:30 in Los Angeles is already the next day in UTC; the day picked
    /// is the day kept.
    @Test func theDayIsTheOneThePickerShowed() {
        let losAngeles = Calendar.gregorian(in: "America/Los_Angeles")
        let picked = losAngeles.at(1990, 5, 1, 23, 30)

        let birthDate = BirthDate(picked, in: losAngeles.timeZone)

        #expect(birthDate.dayString == "1990-05-01")
        #expect(BirthDate(birthDate.date(in: losAngeles.timeZone), in: losAngeles.timeZone) == birthDate)
    }

    @Test func theWheelStopsThirteenYearsAgo() {
        let madrid = Calendar.gregorian(in: "Europe/Madrid")

        let latest = BirthDate.latest(now: madrid.at(2026, 10, 12, 9), in: madrid.timeZone)

        #expect(BirthDate(latest, in: madrid.timeZone).dayString == "2013-10-12")
    }

    @Test func theSignUpMetadataCarriesTheDay() {
        let metadata = AuthManager.signUpMetadata(name: MemberName(first: "Mara", last: "Lopez"),
                                                  birthDate: BirthDate(dayString: "1990-05-01"))

        #expect(metadata?["date_of_birth"]?.stringValue == "1990-05-01")
    }

    // MARK: - The account form

    @MainActor @Test func anEmailAccountNeedsADateOfBirth() {
        let vm = AccountViewModel(mode: .createAccount)
        vm.firstName = "Mara"
        vm.lastName = "Lopez"
        vm.email = "mara@example.com"
        vm.password = "long-enough"
        #expect(!vm.canSubmit)

        vm.dateOfBirth = Calendar.gregorian(in: "Europe/Madrid").at(1990, 5, 1, 12)

        #expect(vm.canSubmit)
    }

    /// The retreat form once sent the team a birthday nobody chose, because
    /// opening its wheel wrote the starting date in.
    @MainActor @Test func openingTheWheelIsNotAnAnswer() {
        let vm = AccountViewModel(mode: .createAccount)

        _ = vm.dateOfBirthWheel

        #expect(vm.dateOfBirth == nil)
    }

    // MARK: - The You tab

    @MainActor final class Saved {
        var name: MemberName?
        var birthDate: BirthDate?
    }

    @MainActor @Test func aDateOfBirthAloneCanBeAddedFromTheYouTab() async {
        let saved = Saved()
        let name = MemberName(first: "Mara", last: "Lopez")
        let vm = EditNameViewModel(current: name) { saved.name = $0; saved.birthDate = $1 }
        #expect(!vm.canSave)

        vm.dateOfBirth = BirthDate(dayString: "1990-05-01")?.date()

        #expect(vm.canSave)
        #expect(await vm.save())
        #expect(saved.name == name)
        #expect(saved.birthDate == BirthDate(dayString: "1990-05-01"))
    }

    @MainActor @Test func theEditorOpensOnTheDateGiven() {
        let birthDate = BirthDate(dayString: "1990-05-01")
        let vm = EditNameViewModel(current: MemberName(first: "Mara", last: "Lopez"),
                                   birthDate: birthDate) { _, _ in }

        #expect(vm.birthDate == birthDate)
        #expect(!vm.canSave)
    }

    // MARK: - The retreat form

    @MainActor @Test func theRetreatFormOpensOnTheAccountsDateOfBirth() {
        let vm = RetreatEnquiryViewModel(retreat: Fixtures.retreat(), name: MemberName(first: "Mara"),
                                         birthDate: BirthDate(dayString: "1990-05-01"))

        #expect(vm.dateOfBirth.map { BirthDate($0) } == BirthDate(dayString: "1990-05-01"))
        #expect(!vm.hasContent)
    }

    /// Guests are adults: a member under 18 answers for themselves, where
    /// the wheel stops.
    @MainActor @Test func aMinorsDateOfBirthIsNotPrefilled() {
        let fifteen = BirthDate(Calendar.current.date(byAdding: .year, value: -15, to: Date())!)

        let vm = RetreatEnquiryViewModel(retreat: Fixtures.retreat(), name: MemberName(first: "Mara"),
                                         birthDate: fifteen)

        #expect(vm.dateOfBirth == nil)
    }
}
