//
//  WrittenSittingTests.swift
//  SoulfullTests
//
//  What a written practice writes to the ledger, and when. Two ways it used to
//  lose a finish: a reflection first written after half an hour on the screen
//  (time had stopped growing at the cap, and only more time was written), and
//  a prompt left open in a kept tab and written in the next day (its heartbeats
//  went to yesterday's row, which the server had closed). The clock arithmetic
//  itself is DwellClockTests.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Written sitting")
struct WrittenSittingTests {

    let calendar = Calendar.gregorian(in: "Europe/Madrid")
    /// 22:00 on Wednesday 16 September 2026, Madrid.
    var opened: Date { calendar.at(2026, 9, 16, 22) }

    func at(_ seconds: TimeInterval) -> Date { opened.addingTimeInterval(seconds) }

    func sittingOnScreen() -> WrittenSitting {
        var sitting = WrittenSitting()
        _ = sitting.appeared(at: opened, foreground: true, calendar: calendar)
        return sitting
    }

    // MARK: - What gets written

    @Test func aGlanceWritesNothing() {
        var sitting = sittingOnScreen()

        #expect(sitting.report(at: at(3), isComplete: { _ in false }) == nil)
    }

    @Test func timeOnScreenIsWrittenOnceAndThenOnlyWhenItGrows() {
        var sitting = sittingOnScreen()

        let first = sitting.report(at: at(30), isComplete: { _ in false })
        let again = sitting.report(at: at(30), isComplete: { _ in false })

        #expect(first?.seconds == 30)
        #expect(again == nil)
    }

    /// The bug: at the cap, dwell stopped growing, and the only thing that
    /// triggered a write was more dwell.
    @Test func aFinishAfterTheCapIsStillWritten() {
        var sitting = sittingOnScreen()
        let pastTheCap = DwellClock.maxDwell + 60
        _ = sitting.report(at: at(pastTheCap), isComplete: { _ in false })

        let finished = sitting.report(at: at(pastTheCap + 120), isComplete: { _ in true })

        #expect(finished?.completed == true)
        #expect(finished?.seconds == Int(DwellClock.maxDwell))
    }

    @Test func aFinishAlreadyWrittenIsNotWrittenAgain() {
        var sitting = sittingOnScreen()
        _ = sitting.report(at: at(DwellClock.maxDwell + 60), isComplete: { _ in true })

        #expect(sitting.report(at: at(DwellClock.maxDwell + 120), isComplete: { _ in true }) == nil)
    }

    // MARK: - One day, one sitting

    /// The bug: the same row, the next morning.
    @Test func comingBackOnALaterDayBeginsANewSitting() {
        var sitting = sittingOnScreen()
        _ = sitting.report(at: at(60), isComplete: { _ in false })
        let yesterday = sitting.eventID
        _ = sitting.sceneChanged(active: false, at: at(120), calendar: calendar)

        let nextMorning = calendar.at(2026, 9, 17, 8)
        let renewed = sitting.sceneChanged(active: true, at: nextMorning, calendar: calendar)

        #expect(renewed)
        #expect(sitting.eventID != yesterday)
        #expect(sitting.clock.dwell(at: nextMorning.addingTimeInterval(10)) == 10)
    }

    @Test func aNewSittingWritesItsFinishEvenIfYesterdaysWasWritten() {
        var sitting = sittingOnScreen()
        _ = sitting.report(at: at(60), isComplete: { _ in true })
        sitting.disappeared(at: at(90))
        let nextMorning = calendar.at(2026, 9, 17, 8)
        _ = sitting.appeared(at: nextMorning, foreground: true, calendar: calendar)

        let today = sitting.report(at: nextMorning.addingTimeInterval(60), isComplete: { _ in true })

        #expect(today?.completed == true)
        #expect(today?.seconds == 60)
    }

    @Test func comingBackTheSameDayContinuesTheSitting() {
        var sitting = sittingOnScreen()
        let first = sitting.eventID
        _ = sitting.sceneChanged(active: false, at: at(60), calendar: calendar)

        let renewed = sitting.sceneChanged(active: true, at: at(1_200), calendar: calendar)

        #expect(!renewed)
        #expect(sitting.eventID == first)
        #expect(sitting.clock.dwell(at: at(1_230)) == 90)
    }

    /// Reading on through midnight is one sitting; only a return is a new one.
    @Test func aSittingThatRunsPastMidnightStaysOneSitting() {
        var sitting = sittingOnScreen()
        let first = sitting.eventID

        let renewed = sitting.appeared(at: calendar.at(2026, 9, 17, 0, 30), foreground: true,
                                       calendar: calendar)

        #expect(!renewed)
        #expect(sitting.eventID == first)
    }

    @Test func returningToAScreenUnderAnotherDoesNotRenewItWhileItStaysHidden() {
        var sitting = sittingOnScreen()
        let first = sitting.eventID
        sitting.disappeared(at: at(60))

        let renewed = sitting.sceneChanged(active: true, at: calendar.at(2026, 9, 17, 8),
                                           calendar: calendar)

        #expect(!renewed)
        #expect(sitting.eventID == first)
    }
}
