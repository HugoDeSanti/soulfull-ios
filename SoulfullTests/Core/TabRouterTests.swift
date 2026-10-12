//
//  TabRouterTests.swift
//  SoulfullTests
//
//  The shell's state, now that each tab's page is built once and reads it
//  from `TabRouter` instead of being rebuilt with it: a hand-off names what to
//  open and switches tab in one step, the account gate holds a guest's tap
//  for the sheet, and the nav hides only for the tab that is showing. The
//  tabs themselves are covered end to end by SoulfullUITests
//  (GatheringsTabTests, ProgramTests, AccountGateTests…).
//

import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Tab router")
struct TabRouterTests {

    @Test func openingARetreatHandsItToGatheringsAndGoesThere() {
        let router = TabRouter()
        let mallorca = Fixtures.retreat()

        router.openRetreat(mallorca)

        #expect(router.tab == .gatherings)
        #expect(router.pendingRetreat == mallorca)
    }

    @Test func openingAPracticeSectionHandsItToPractice() {
        let router = TabRouter()

        router.openPractice(.journal)

        #expect(router.tab == .practice)
        #expect(router.pendingPractice == .journal)
    }

    @Test func openingAProgramHandsItToDigitalRetreats() {
        let router = TabRouter(tab: .you)

        router.openProgram("finding-ground")

        #expect(router.tab == .programs)
        #expect(router.pendingProgram == "finding-ground")
    }

    @Test func aTappedLikeOpensCommunityOnItsNotifications() {
        let router = TabRouter()

        router.openNotifications()

        #expect(router.tab == .community)
        #expect(router.pendingNotifications)
    }

    // MARK: - The account gate

    @Test func aMembersTapGoesStraightThrough() {
        let router = TabRouter()
        var ran = false

        router.requireAccount(signedIn: true) { ran = true }

        #expect(ran)
        #expect(!router.showAccount)
    }

    @Test func aGuestsTapWaitsForTheSheetAndRunsOnceTheyHaveAnAccount() {
        let router = TabRouter()
        var ran = false

        router.requireAccount(signedIn: false) { ran = true }
        #expect(router.showAccount)
        #expect(!ran)

        router.resumeAfterAccountSheet(signedIn: true)

        #expect(ran)
    }

    @Test func aGuestWhoClosesTheSheetLosesTheTap() {
        let router = TabRouter()
        var ran = false
        router.requireAccount(signedIn: false) { ran = true }

        router.resumeAfterAccountSheet(signedIn: false)

        #expect(!ran)
    }

    // MARK: - The nav bar

    /// Every tab keeps its stack: a screen pushed on Gatherings mustn't hide
    /// the nav while Home is showing.
    @Test func theNavHidesOnlyForTheShowingTabsPush() {
        let router = TabRouter(tab: .home)

        router.navHidden(.gatherings).wrappedValue = true

        #expect(!router.isNavHidden)
        router.tab = .gatherings
        #expect(router.isNavHidden)
        router.navHidden(.gatherings).wrappedValue = false
        #expect(!router.isNavHidden)
    }
}
