//
//  AccountConfirmationPanelTests.swift
//  SoulfullTests
//
//  Getting on and off the confirm-your-email panel. A sheet reopened while a
//  confirmation is pending goes back to the code for the right address, and
//  leaving the panel doesn't carry its messages onto the form.
//

import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Account confirmation panel")
struct AccountConfirmationPanelTests {

    @Test func aResumedConfirmationOpensOnTheCodeForThatAddress() {
        let vm = AccountViewModel(mode: .signIn)

        vm.resumeConfirmation(for: "mara@example.com")

        #expect(vm.awaitingConfirmation)
        #expect(vm.confirmationEmail == "mara@example.com")
    }

    @Test func leavingThePanelLeavesItsMessagesBehind() {
        let vm = AccountViewModel()
        vm.resumeConfirmation(for: "mara@example.com")
        vm.confirmationCode = "123456"
        vm.errorMessage = "That code didn't work."
        vm.resendMessage = "Sent — check your inbox again."

        vm.leaveConfirmation()

        #expect(!vm.awaitingConfirmation)
        #expect(vm.errorMessage == nil)
        #expect(vm.resendMessage == nil)
        #expect(vm.confirmationCode.isEmpty)
    }
}
