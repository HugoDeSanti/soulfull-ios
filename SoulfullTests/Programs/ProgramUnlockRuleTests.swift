//
//  ProgramUnlockRuleTests.swift
//  SoulfullTests
//
//  The rule the Programs tab hangs off:
//
//      Day 1 opens when you enrol.
//      Day N+1 opens when every activity in Day N is complete AND the local
//      calendar date has moved past the date Day N was finished on.
//
//  A program is paced — finishing Thursday's practices at 9pm does not hand
//  you Friday's at 9:01, and it doesn't make you wait 24 hours either.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Program unlock rule")
struct ProgramUnlockRuleTests {

    let calendar = Calendar.gregorian(in: "Europe/Madrid")
    var enrolledAt: Date { calendar.at(2026, 9, 14, 18) }

    func state(day: Int, completions: [Int: Date] = [:], at now: Date) -> ProgramDayState {
        ProgramUnlockRule.state(day: day, enrolledAt: enrolledAt, completions: completions,
                                now: now, calendar: calendar)
    }

    @Test func dayOneOpensTheMomentYouEnrol() {
        #expect(state(day: 1, at: enrolledAt) == .open)
    }

    @Test func withoutAnEnrolmentNoDayIsReachable() {
        #expect(ProgramUnlockRule.unlockedAt(day: 1, enrolledAt: nil, completions: [:],
                                             calendar: calendar) == nil)
        #expect(ProgramUnlockRule.state(day: 1, enrolledAt: nil, completions: [:],
                                        now: enrolledAt, calendar: calendar) == .awaitingPreviousDay)
    }

    @Test func theNextDayWaitsForThePreviousOneToBeFinished() {
        let muchLater = calendar.at(2026, 9, 30, 12)

        #expect(state(day: 2, at: muchLater) == .awaitingPreviousDay)
    }

    @Test func finishingAt9pmOpensTheNextDayAtMidnightNot24HoursLater() {
        let finished = calendar.at(2026, 9, 14, 21)
        let midnight = calendar.at(2026, 9, 15)

        #expect(state(day: 2, completions: [1: finished], at: calendar.at(2026, 9, 14, 23, 59))
                == .opens(midnight))
        #expect(state(day: 2, completions: [1: finished], at: midnight) == .open)
    }

    @Test func finishingJustAfterMidnightStillWaitsForTheDateToChange() {
        let finished = calendar.at(2026, 9, 15, 0, 5)

        #expect(state(day: 2, completions: [1: finished], at: calendar.at(2026, 9, 15, 23))
                == .opens(calendar.at(2026, 9, 16)))
    }

    @Test func aFinishedDayReportsWhenItWasFinished() {
        let finished = calendar.at(2026, 9, 15, 8)

        #expect(state(day: 1, completions: [1: finished], at: calendar.at(2026, 9, 20))
                == .complete(finished))
    }

    /// Madrid's clocks go back at 03:00 on 25 October 2026, so that day is 25
    /// hours long. A day finished on it opens at midnight on the 26th — adding
    /// 86,400 seconds to the start of the 25th would open it an hour early.
    @Test func theNextDayOpensAtLocalMidnightAcrossAClockChange() {
        let finished = calendar.at(2026, 10, 25, 10)

        let unlock = ProgramUnlockRule.unlockedAt(day: 2, enrolledAt: enrolledAt,
                                                  completions: [1: finished], calendar: calendar)

        #expect(unlock == calendar.at(2026, 10, 26))
        #expect(state(day: 2, completions: [1: finished], at: calendar.at(2026, 10, 25, 23, 30))
                == .opens(calendar.at(2026, 10, 26)))
    }

    /// `practice_progress.completed` is latched for all time. Without the
    /// date half, anyone with history would find days already done the moment
    /// they enrolled.
    @Test func anActivityCountsOnlyIfItWasFinishedAfterTheDayOpened() {
        let dayOpened = calendar.at(2026, 9, 15)

        let before = Fixtures.progress(completed: true, lastPlayedAt: calendar.at(2026, 9, 14, 20))
        let after = Fixtures.progress(completed: true, lastPlayedAt: calendar.at(2026, 9, 15, 9))
        let unfinished = Fixtures.progress(completed: false, lastPlayedAt: calendar.at(2026, 9, 15, 9))

        #expect(!ProgramUnlockRule.counts(before, towardDayUnlockedAt: dayOpened))
        #expect(ProgramUnlockRule.counts(after, towardDayUnlockedAt: dayOpened))
        #expect(!ProgramUnlockRule.counts(unfinished, towardDayUnlockedAt: dayOpened))
        #expect(!ProgramUnlockRule.counts(nil, towardDayUnlockedAt: dayOpened))
        #expect(!ProgramUnlockRule.counts(after, towardDayUnlockedAt: nil))
    }
}
