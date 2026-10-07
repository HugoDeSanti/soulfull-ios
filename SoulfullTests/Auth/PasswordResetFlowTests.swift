//
//  PasswordResetFlowTests.swift
//  SoulfullTests
//
//  "Forgot password?" on the account sheet: the address carries over, a code
//  goes out whether or not the address has an account, and the code is spent
//  once. A refused password after an accepted code mustn't send the code
//  again, because it's single-use and they're already signed in by then.
//

import Foundation
import Testing
@preconcurrency import Supabase
@testable import SoulfullGatherings

/// A GoTrue error response, shaped the way the SDK throws it.
private func goTrue(_ status: Int, _ code: ErrorCode) -> AuthError {
    .api(message: "", errorCode: code, underlyingData: Data(),
         underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.supabase.co/auth/v1/verify")!,
                                             statusCode: status, httpVersion: nil, headerFields: nil)!)
}

@MainActor
@Suite("Password reset")
struct PasswordResetFlowTests {

    /// Stands in for GoTrue's `/recover`, `/verify` and `PUT /user`, and
    /// records what the steps asked of it.
    @MainActor
    final class Server {
        var sendFailure: (any Error)?
        var verifyFailure: (any Error)?
        /// Thrown by successive password attempts; nil means it's accepted.
        var passwordFailures: [(any Error)?] = []

        private(set) var codesSentTo: [String] = []
        private(set) var codesVerified: [(code: String, email: String)] = []
        private(set) var passwordsSet: [String] = []
        private(set) var signIns = 0

        var backend: AccountViewModel.PasswordResetBackend {
            .init(
                sendCode: { email in
                    self.codesSentTo.append(email)
                    if let failure = self.sendFailure { throw failure }
                },
                verifyCode: { code, email in
                    self.codesVerified.append((code, email))
                    if let failure = self.verifyFailure { throw failure }
                },
                setPassword: { password in
                    self.passwordsSet.append(password)
                    if !self.passwordFailures.isEmpty, let failure = self.passwordFailures.removeFirst() {
                        throw failure
                    }
                },
                signedIn: { self.signIns += 1 }
            )
        }
    }

    /// The sheet as it stands once the code is on its way to Mara.
    private func onTheCodeStep(_ server: Server) async -> AccountViewModel {
        let vm = AccountViewModel(mode: .signIn)
        vm.email = "mara@example.com"
        vm.beginPasswordReset()
        await vm.sendResetCode(server.backend)
        return vm
    }

    // MARK: - Asking for a code

    @Test func forgotPasswordKeepsTheAddressButNotThePasswordThatFailed() {
        let vm = AccountViewModel(mode: .signIn)
        vm.email = "mara@example.com"
        vm.password = "not-quite-right"
        vm.errorMessage = "That email and password didn't match. Try again."

        vm.beginPasswordReset()

        #expect(vm.passwordReset == .request)
        #expect(vm.email == "mara@example.com")
        #expect(vm.password.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test(arguments: [
        ("mara@example.com", true),
        (" mara@example.com ", true),
        ("mara@example", false),
        ("", false),
    ])
    func aCodeCanBeAskedForOnlyForAPlausibleAddress(email: String, allowed: Bool) {
        let vm = AccountViewModel(mode: .signIn)
        vm.email = email

        vm.beginPasswordReset()

        #expect(vm.canSendResetCode == allowed)
    }

    /// GoTrue answers the same for an address with no account, so the sheet
    /// can't, and mustn't, tell the two apart.
    @Test func aSentCodeMovesOnToTheCodeForTheTrimmedAddress() async {
        let server = Server()
        let vm = AccountViewModel(mode: .signIn)
        vm.email = "  mara@example.com "
        vm.beginPasswordReset()

        await vm.sendResetCode(server.backend)

        #expect(server.codesSentTo == ["mara@example.com"])
        #expect(vm.passwordReset == .newPassword)
        #expect(vm.email == "mara@example.com")
        #expect(vm.resendCooldown == 60)
    }

    @Test func aRequestThatDidntGoOutStaysOnTheAddressAndSaysWhy() async {
        let server = Server()
        server.sendFailure = URLError(.notConnectedToInternet)

        let vm = await onTheCodeStep(server)

        #expect(vm.passwordReset == .request)
        #expect(vm.errorMessage == AuthFailureCopy.offline)
        #expect(vm.resendCooldown == 0)
    }

    /// A new code replaces the old one on the server.
    @Test func aResentCodeClearsTheOneTypedFromTheOldEmail() async {
        let server = Server()
        let vm = AccountViewModel(mode: .signIn)
        vm.email = "mara@example.com"
        vm.passwordReset = .newPassword
        vm.resetCode = "123456"

        await vm.resendResetCode(server.backend)

        #expect(server.codesSentTo == ["mara@example.com"])
        #expect(vm.resetCode.isEmpty)
        #expect(vm.resendMessage != nil)
        #expect(vm.resendCooldown == 60)
    }

    @Test func backToSignInKeepsTheAddressAndDropsTheRest() async {
        let server = Server()
        server.verifyFailure = goTrue(403, .otpExpired)
        let vm = await onTheCodeStep(server)
        vm.resetCode = "111111"
        vm.newPassword = "a-new-password"
        _ = await vm.setNewPassword(server.backend)

        vm.leavePasswordReset()

        #expect(vm.passwordReset == nil)
        #expect(vm.mode == .signIn)
        #expect(vm.email == "mara@example.com")
        #expect(vm.resetCode.isEmpty)
        #expect(vm.newPassword.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - The code and the new password

    @Test(arguments: [
        ("123456", "eight888", true),
        ("12345", "eight888", false),     // a code is six digits at least
        ("123456", "seven77", false),     // the same rule as creating an account
        ("12-34 56", "eight888", true),   // pasted with separators
    ])
    func theNewPasswordWaitsForACodeAndEightCharacters(code: String, password: String, allowed: Bool) {
        let vm = AccountViewModel(mode: .signIn)
        vm.email = "mara@example.com"
        vm.passwordReset = .newPassword

        vm.resetCode = code
        vm.newPassword = password

        #expect(vm.canSetNewPassword == allowed)
    }

    @Test func theRightCodeSignsThemInAndSetsTheirNewPassword() async {
        let server = Server()
        let vm = await onTheCodeStep(server)
        vm.resetCode = "482913"
        vm.newPassword = "a-new-password"

        let outcome = await vm.setNewPassword(server.backend)

        #expect(outcome == .signedIn)
        #expect(server.codesVerified.map { $0.code } == ["482913"])
        #expect(server.codesVerified.map { $0.email } == ["mara@example.com"])
        #expect(server.passwordsSet == ["a-new-password"])
        #expect(server.signIns == 1)
        #expect(vm.newPassword.isEmpty)
    }

    @Test func aWrongCodeSetsNoPasswordAndLeavesTheCodeToFix() async {
        let server = Server()
        server.verifyFailure = goTrue(403, .otpExpired)
        let vm = await onTheCodeStep(server)
        vm.resetCode = "111111"
        vm.newPassword = "a-new-password"

        let outcome = await vm.setNewPassword(server.backend)

        #expect(outcome == .failed)
        #expect(server.passwordsSet.isEmpty)
        #expect(server.signIns == 0)
        #expect(!vm.resetCodeAccepted)
        #expect(vm.resetCode == "111111")
        #expect(vm.errorMessage == AuthFailureCopy.message(for: goTrue(403, .otpExpired), during: .confirmCode))
    }

    /// The code is spent the moment it's accepted. Sending it again with the
    /// second password would fail as expired and strand them.
    @Test func aRefusedPasswordIsRetriedWithoutSpendingTheCodeAgain() async {
        let server = Server()
        server.passwordFailures = [AuthError.weakPassword(message: "", reasons: ["length"]), nil]
        let vm = await onTheCodeStep(server)
        vm.resetCode = "482913"
        vm.newPassword = "password"

        let first = await vm.setNewPassword(server.backend)

        #expect(first == .failed)
        #expect(vm.resetCodeAccepted)
        #expect(server.signIns == 1)
        #expect(vm.canSetNewPassword == true)
        #expect(vm.errorMessage == AuthFailureCopy.message(for: AuthError.weakPassword(message: "", reasons: []),
                                                          during: .newPassword))

        vm.newPassword = "a much longer one"
        let second = await vm.setNewPassword(server.backend)

        #expect(second == .signedIn)
        #expect(server.codesVerified.count == 1)
        #expect(server.passwordsSet == ["password", "a much longer one"])
        #expect(server.signIns == 1)
    }

    /// Typing the password the account already has gets GoTrue's
    /// `same_password`. It works and they now know it, which is the point.
    @Test func thePasswordTheyAlreadyHadCountsAsDone() async {
        let server = Server()
        server.passwordFailures = [goTrue(422, .samePassword)]
        let vm = await onTheCodeStep(server)
        vm.resetCode = "482913"
        vm.newPassword = "the-old-one"

        let outcome = await vm.setNewPassword(server.backend)

        #expect(outcome == .signedIn)
        #expect(vm.errorMessage == nil)
    }
}
