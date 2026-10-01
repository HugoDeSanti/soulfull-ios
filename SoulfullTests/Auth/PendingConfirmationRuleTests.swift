//
//  PendingConfirmationRuleTests.swift
//  SoulfullTests
//
//  When the account sheet opens on the code panel rather than a blank form.
//  A guest who created an account, closed the sheet and came back used to get
//  the form again, and a second submit either hit the send rate limit or
//  invalidated the code they already had. After a relaunch the only record is
//  the stored guest's pending `new_email`.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Pending confirmation")
struct PendingConfirmationRuleTests {

    private let madrid = Calendar.gregorian(in: "Europe/Madrid")
    private var now: Date { madrid.at(2026, 10, 1, 12) }

    private func guest(pending address: String?, sentHoursAgo hours: Double? = 2) -> PendingConfirmationRule.StoredUser {
        PendingConfirmationRule.StoredUser(isAnonymous: true, newEmail: address,
                                           sentAt: hours.map { now.addingTimeInterval(-$0 * 3600) })
    }

    @Test func aSignUpStartedThisLaunchReopensOnItsCode() {
        let address = PendingConfirmationRule.address(
            hasAccount: false, startedThisLaunch: "mara@example.com", setAside: false,
            storedUser: guest(pending: nil), now: now)

        #expect(address == "mara@example.com")
    }

    @Test func afterARelaunchTheGuestsPendingAddressReopensOnItsCode() {
        let address = PendingConfirmationRule.address(
            hasAccount: false, startedThisLaunch: nil, setAside: false,
            storedUser: guest(pending: "mara@example.com"), now: now)

        #expect(address == "mara@example.com")
    }

    @Test func aConfirmedAccountOpensOnTheForm() {
        let address = PendingConfirmationRule.address(
            hasAccount: true, startedThisLaunch: "mara@example.com", setAside: false,
            storedUser: guest(pending: "mara@example.com"), now: now)

        #expect(address == nil)
    }

    /// "Use a different sign-in" means it, for the rest of the launch.
    @Test func choosingADifferentSignInOpensOnTheForm() {
        let address = PendingConfirmationRule.address(
            hasAccount: false, startedThisLaunch: nil, setAside: true,
            storedUser: guest(pending: "mara@example.com"), now: now)

        #expect(address == nil)
    }

    @Test(arguments: [(23.5, true), (24.5, false)])
    func aSignUpAbandonedForADayStopsReopening(hoursAgo: Double, reopens: Bool) {
        let address = PendingConfirmationRule.address(
            hasAccount: false, startedThisLaunch: nil, setAside: false,
            storedUser: guest(pending: "mara@example.com", sentHoursAgo: hoursAgo), now: now)

        #expect((address != nil) == reopens)
    }

    @Test func aPendingAddressWithNoSendTimeOpensOnTheForm() {
        let address = PendingConfirmationRule.address(
            hasAccount: false, startedThisLaunch: nil, setAside: false,
            storedUser: guest(pending: "mara@example.com", sentHoursAgo: nil), now: now)

        #expect(address == nil)
    }

    /// Only a guest's upgrade is a sign-up. A member's own email change isn't
    /// this sheet's business.
    @Test func aMembersPendingEmailChangeOpensOnTheForm() {
        var member = guest(pending: "new@example.com")
        member.isAnonymous = false

        let address = PendingConfirmationRule.address(
            hasAccount: false, startedThisLaunch: nil, setAside: false,
            storedUser: member, now: now)

        #expect(address == nil)
    }

    @Test func aGuestWithNothingPendingOpensOnTheForm() {
        let address = PendingConfirmationRule.address(
            hasAccount: false, startedThisLaunch: nil, setAside: false,
            storedUser: guest(pending: "  "), now: now)

        #expect(address == nil)
    }
}
