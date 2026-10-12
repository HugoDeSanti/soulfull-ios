//
//  RelativeTimeTests.swift
//  SoulfullTests
//
//  When something happened, as the feed and a practice's comments say it.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@Suite("Relative time")
struct RelativeTimeTests {

    let madrid = Calendar.gregorian(in: "Europe/Madrid")

    @Test func theLastHourIsCountedInMinutes() {
        let now = madrid.at(2026, 10, 12, 12)

        #expect(RelativeTime.label(now.addingTimeInterval(-30), now: now, calendar: madrid) == "just now")
        #expect(RelativeTime.label(now.addingTimeInterval(-12 * 60), now: now, calendar: madrid) == "12 min ago")
    }

    @Test func earlierTodayIsCountedInHours() {
        let now = madrid.at(2026, 10, 12, 12)

        #expect(RelativeTime.label(madrid.at(2026, 10, 12, 8, 50), now: now, calendar: madrid) == "3 hr ago")
    }

    @Test func aMomentAheadOfThePhonesClockIsJustNow() {
        let now = madrid.at(2026, 10, 12, 12)

        #expect(RelativeTime.label(now.addingTimeInterval(90), now: now, calendar: madrid) == "just now")
    }

    @Test func pastTheHourYesterdayIsTheCalendarDay() {
        // An hour and forty minutes ago, but before midnight. Inside the hour
        // it would still be minutes: "20 min ago" reads better than
        // "yesterday" for something just now.
        let now = madrid.at(2026, 10, 12, 0, 10)

        #expect(RelativeTime.label(madrid.at(2026, 10, 11, 22, 30), now: now, calendar: madrid) == "yesterday")
        #expect(RelativeTime.label(madrid.at(2026, 10, 11, 23, 50), now: now, calendar: madrid) == "20 min ago")
    }

    @Test func yesterdayHoldsAcrossTheLongDay() {
        // Madrid's 25 October 2026 is 25 hours long.
        let now = madrid.at(2026, 10, 26, 0, 30)

        #expect(RelativeTime.label(madrid.at(2026, 10, 25, 1), now: now, calendar: madrid) == "yesterday")
    }

    @Test func thisWeekIsTheWeekdayAndOlderIsTheDate() {
        let now = madrid.at(2026, 10, 12, 12)   // a Monday

        #expect(RelativeTime.label(madrid.at(2026, 10, 9, 18), now: now, calendar: madrid) == "Friday")
        // "12 Sep" or "Sep 12", as the phone's region writes it.
        let older = RelativeTime.label(madrid.at(2026, 9, 12, 18), now: now, calendar: madrid)
        #expect(older.contains("12") && older.contains("Sep"))
    }
}
