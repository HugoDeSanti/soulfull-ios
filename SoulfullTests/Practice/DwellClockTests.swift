//
//  DwellClockTests.swift
//  SoulfullTests
//
//  What a written practice's creator is credited for: time its screen was
//  actually in front of the member. Leaving for another screen or the home
//  screen stops the clock and banks the sitting; coming back continues it.
//  A visit is capped, because a screen left open is not reading.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Dwell clock")
struct DwellClockTests {

    let opened = Calendar.gregorian(in: "Europe/Madrid").at(2026, 9, 16, 12)

    func at(_ seconds: TimeInterval) -> Date { opened.addingTimeInterval(seconds) }

    /// A clock started on a screen that appeared at `opened`, in the foreground.
    func clockOnScreen() -> DwellClock {
        var clock = DwellClock()
        clock.appeared(at: opened, foreground: true)
        return clock
    }

    @Test func nothingIsCountedBeforeTheScreenAppears() {
        let clock = DwellClock()

        #expect(!clock.hasStarted)
        #expect(clock.dwell(at: at(60)) == 0)
    }

    @Test func timeOnScreenCounts() {
        let clock = clockOnScreen()

        #expect(clock.hasStarted)
        #expect(clock.dwell(at: at(30)) == 30)
    }

    /// The bug this type exists for: a recipe left for its guide's page and
    /// returned to restarted from zero, so it never reached 45 seconds.
    @Test func leavingForAnotherScreenAndComingBackContinuesTheCount() {
        var clock = clockOnScreen()

        clock.disappeared(at: at(20))
        clock.appeared(at: at(100), foreground: true)

        #expect(clock.dwell(at: at(130)) == 50)
    }

    @Test func timeUnderAPushedScreenIsNotCounted() {
        var clock = clockOnScreen()

        clock.disappeared(at: at(20))

        #expect(clock.dwell(at: at(600)) == 20)
        #expect(clock.hasStarted)
    }

    /// SwiftUI can deliver `onAppear` again without an `onDisappear` between;
    /// that must not restart the sitting under way.
    @Test func appearingAgainWhileOnScreenChangesNothing() {
        var clock = clockOnScreen()

        clock.appeared(at: at(10), foreground: true)

        #expect(clock.dwell(at: at(30)) == 30)
    }

    @Test func backgroundingStopsTheClockAndReturningContinuesIt() {
        var clock = clockOnScreen()

        clock.sceneChanged(active: false, at: at(10))
        clock.sceneChanged(active: true, at: at(8 * 3600))

        #expect(clock.dwell(at: at(8 * 3600 + 10)) == 20)
    }

    /// A page under a pushed screen still hears the scene come back; it
    /// mustn't start counting while it can't be seen.
    @Test func returningToTheAppWhileCoveredDoesNotRestartTheClock() {
        var clock = clockOnScreen()

        clock.disappeared(at: at(10))
        clock.sceneChanged(active: false, at: at(20))
        clock.sceneChanged(active: true, at: at(30))

        #expect(clock.dwell(at: at(300)) == 10)
    }

    @Test func appearingOutsideTheForegroundWaitsForIt() {
        var clock = DwellClock()

        clock.appeared(at: opened, foreground: false)
        clock.sceneChanged(active: true, at: at(40))

        #expect(clock.dwell(at: at(70)) == 30)
    }

    @Test func aSingleSittingIsCappedAtThirtyMinutes() {
        let clock = clockOnScreen()

        #expect(clock.dwell(at: at(2 * 3600)) == DwellClock.maxDwell)
    }

    @Test func theCapCoversEverySittingOfTheVisit() {
        var clock = clockOnScreen()

        clock.disappeared(at: at(25 * 60))
        clock.appeared(at: at(26 * 60), foreground: true)

        #expect(clock.dwell(at: at(36 * 60)) == DwellClock.maxDwell)
    }
}
