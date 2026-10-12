//
//  AccountFormTests.swift
//  SoulfullTests
//
//  When the create-account / sign-in form lets someone submit, and what the
//  confirmation-code field accepts. The auth calls themselves go to Supabase
//  and are not exercised here.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Account form")
struct AccountFormTests {

    @Test(arguments: [
        (AccountViewModel.Mode.createAccount, MemberName(first: "Mara", last: "Lopez"),
         "mara@example.com", "long-enough", true),
        (.createAccount, MemberName(first: "  ", last: " "), "mara@example.com", "long-enough", false),  // a name is asked for
        (.createAccount, MemberName(first: "Mara"), "mara@example.com", "long-enough", false),           // both parts of it
        (.createAccount, MemberName(last: "Lopez"), "mara@example.com", "long-enough", false),
        (.signIn, MemberName(), "mara@example.com", "long-enough", true),                                // …but not to sign in
        (.signIn, MemberName(), " mara@example.com ", "long-enough", true),
        (.signIn, MemberName(), "mara@example", "long-enough", false),
        (.signIn, MemberName(), "mara.example.com", "long-enough", false),
        (.signIn, MemberName(), "mara@example.com", "seven77", false),
    ])
    func submitWaitsForANamePlausibleAddressAnd8CharacterPassword(
        mode: AccountViewModel.Mode, name: MemberName, email: String, password: String, allowed: Bool
    ) {
        let vm = AccountViewModel(mode: mode)
        vm.firstName = name.first
        vm.lastName = name.last
        vm.dateOfBirth = mode == .createAccount ? Date(timeIntervalSince1970: 641_563_200) : nil  // 1990-05-01
        vm.email = email
        vm.password = password

        #expect(vm.canSubmit == allowed)
    }

    @Test func nothingCanBeSubmittedTwiceWhileWorking() {
        let vm = AccountViewModel(mode: .signIn)
        vm.email = "mara@example.com"
        vm.password = "long-enough"

        vm.isWorking = true

        #expect(!vm.canSubmit)
    }

    /// Pasted codes arrive with spaces and dashes; the project's OTP length
    /// is 6–10 and the client can't read which, so it keeps digits up to ten.
    @Test func aConfirmationCodeKeepsOnlyDigitsUpToTen() {
        let vm = AccountViewModel()

        vm.confirmationCode = "12 34-56ab 7890 123"

        #expect(vm.confirmationCode == "1234567890")
    }

    @Test(arguments: [("12345", false), ("123456", true), ("1234567890", true)])
    func aCodeCanBeConfirmedFromSixDigits(code: String, confirmable: Bool) {
        let vm = AccountViewModel()

        vm.confirmationCode = code

        #expect(vm.canConfirm == confirmable)
    }
}
