//
//  Fixtures.swift
//  SoulfullTests
//
//  Shared test inputs. Everything date-shaped is pinned to a named time zone,
//  so a test reads the same on every machine whatever the simulator's clock
//  and zone happen to be.
//

import Foundation
import SwiftUI
@testable import SoulfullGatherings

extension Calendar {
    /// A Gregorian calendar in `zone` (an IANA identifier such as "Europe/Madrid").
    static func gregorian(in zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// A wall-clock moment in this calendar's zone.
    func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

enum Fixtures {

    /// A retreat with only what the logic under test reads. Dates are built in
    /// the device calendar, as `RetreatRow` parses them.
    static func retreat(id: Int = 1, name: String = "Mallorca", country: String = "Spain",
                        start: DateComponents = DateComponents(year: 2027, month: 7, day: 21),
                        end: DateComponents = DateComponents(year: 2027, month: 7, day: 26)) -> Retreat {
        Retreat(id: id, name: name, country: country,
                startDate: Calendar.current.date(from: start)!,
                endDate: Calendar.current.date(from: end)!,
                maxGuests: 12, priceUsd: 4400, tags: [], blurb: "",
                imageUrl: "", toneTop: .clear, toneMid: .clear, toneBase: .clear)
    }

    static func progress(_ kind: PracticeContentKind = .journal, contentID: Int = 1,
                         completed: Bool, lastPlayedAt: Date) -> PracticeProgress {
        PracticeProgress(kind: kind, contentID: contentID, title: "A practice", creator: nil,
                         category: nil, positionSeconds: 0, durationSeconds: nil,
                         totalSecondsPlayed: 60, completed: completed, playCount: 1,
                         lastPlayedAt: lastPlayedAt)
    }
}
