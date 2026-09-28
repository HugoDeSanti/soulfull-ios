//
//  PracticeStatsTests.swift
//  SoulfullTests
//
//  The four numbers on the You tab, and the streak Home names. Every definition
//  here was decided with the product owner (CLAUDE.md → "You tab — practice
//  stats") and every one fails *quietly*: count a journal entry as a class, or
//  an opened practice as a day, and the screen still shows a plausible number.
//  So each test pairs what must count with what must not.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Practice stats")
struct PracticeStatsTests {

    /// Madrid, so "today" and every day boundary are fixed whatever zone the
    /// simulator is in. Noon on Wednesday 16 September 2026.
    let calendar = Calendar.gregorian(in: "Europe/Madrid")
    var now: Date { calendar.at(2026, 9, 16, 12) }

    /// A sitting started at `hour` local time, `daysAgo` days before today.
    func sitting(_ kind: PracticeContentKind = .session, daysAgo: Int, hour: Int = 9,
                 seconds: Int = 600, completed: Bool = true) -> PracticePlayRecord {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return PracticePlayRecord(eventID: UUID(), kind: kind, secondsPlayed: seconds,
                                  completed: completed,
                                  startedAt: calendar.date(byAdding: .hour, value: hour, to: day)!)
    }

    func stats(_ plays: [PracticePlayRecord]) -> PracticeStats {
        PracticeStats(plays, calendar: calendar, now: now)
    }

    @Test func noHistoryShowsZerosAndNothingPracticedToday() {
        let result = stats([])

        #expect(result.currentStreak == 0)
        #expect(result.bestStreak == 0)
        #expect(result.classesTaken == 0)
        #expect(result.minutesPracticed == 0)
        #expect(!result.keptToday)
        #expect(!result.practicedToday)
    }

    @Test func consecutiveFinishedDaysEndingTodayMakeTheStreak() {
        let result = stats((0...3).map { sitting(daysAgo: $0) })

        #expect(result.currentStreak == 4)
        #expect(result.keptToday)
    }

    @Test func aStreakCarriedByYesterdayIsStillAliveUntilTodayEnds() {
        let result = stats((1...3).map { sitting(daysAgo: $0) })

        #expect(result.currentStreak == 3)
        #expect(!result.keptToday)
        #expect(!result.practicedToday)
    }

    @Test func aMissedDayEndsTheStreakButNotTheBest() {
        let result = stats([sitting(daysAgo: 2), sitting(daysAgo: 3)])

        #expect(result.currentStreak == 0)
        #expect(result.bestStreak == 2)
    }

    @Test func anUnfinishedPracticeTodayIsPracticeButDoesNotKeepTheStreak() {
        let result = stats([
            sitting(.journal, daysAgo: 0, completed: false),
            sitting(daysAgo: 1),
            sitting(daysAgo: 2),
        ])

        #expect(result.currentStreak == 2)
        #expect(!result.keptToday)
        #expect(result.practicedToday)
    }

    @Test func theBestStreakIsTheLongestRunEvenWhenItIsInThePast() {
        let monthAgo = (30...38).map { sitting(daysAgo: $0) }
        let result = stats(monthAgo + [sitting(daysAgo: 0), sitting(daysAgo: 1)])

        #expect(result.bestStreak == 9)
        #expect(result.currentStreak == 2)
    }

    @Test func journalAndRecipesKeepAStreakButAreNeitherClassesNorMinutes() {
        let result = stats([
            sitting(.journal, daysAgo: 0, seconds: 900),
            sitting(.recipe, daysAgo: 1, seconds: 1_200),
        ])

        #expect(result.currentStreak == 2)
        #expect(result.classesTaken == 0)
        #expect(result.minutesPracticed == 0)
    }

    @Test func everyFinishedSittingOfASessionOrMovementIsAClass() {
        let result = stats([
            sitting(.session, daysAgo: 0),
            sitting(.session, daysAgo: 0),           // the same class twice is two
            sitting(.exercise, daysAgo: 1),
            sitting(.session, daysAgo: 1, completed: false),
        ])

        #expect(result.classesTaken == 3)
    }

    @Test func minutesAreTimeSpentInClassesFinishedOrNotRoundedDown() {
        let result = stats([
            sitting(.session, daysAgo: 0, seconds: 600),
            sitting(.exercise, daysAgo: 1, seconds: 300, completed: false),
            sitting(.session, daysAgo: 2, seconds: 59),
            sitting(.session, daysAgo: 3, seconds: -120),   // never subtracts
        ])

        #expect(result.minutesPracticed == 15)             // 959s
    }

    /// Madrid is UTC+2 in September: 00:30 local is still yesterday in UTC.
    /// The day a practice counts toward is the member's own calendar day.
    @Test func aSittingCountsTowardItsLocalCalendarDay() {
        let justAfterMidnight = PracticePlayRecord(
            eventID: UUID(), kind: .session, secondsPlayed: 600, completed: true,
            startedAt: calendar.at(2026, 9, 16, 0, 30))

        #expect(stats([justAfterMidnight]).keptToday)
    }

    /// São Paulo skipped midnight on 4 November 2018 (00:00 → 01:00), so that
    /// day starts at 01:00. A run across it must not split — stepping back
    /// 86,400 seconds from 5 November lands on 3 November at 23:00.
    @Test func aRunSurvivesAClockChangeThatSkipsMidnight() {
        let saoPaulo = Calendar.gregorian(in: "America/Sao_Paulo")
        let skipped = saoPaulo.startOfDay(for: saoPaulo.at(2018, 11, 4, 12))
        #expect(saoPaulo.component(.hour, from: skipped) == 1, "The fixture no longer skips midnight")

        let plays = [3, 4, 5].map { day in
            PracticePlayRecord(eventID: UUID(), kind: .session, secondsPlayed: 600, completed: true,
                               startedAt: saoPaulo.at(2018, 11, day, 12))
        }
        let result = PracticeStats(plays, calendar: saoPaulo, now: saoPaulo.at(2018, 11, 5, 18))

        #expect(result.currentStreak == 3)
        #expect(result.bestStreak == 3)
    }
}
