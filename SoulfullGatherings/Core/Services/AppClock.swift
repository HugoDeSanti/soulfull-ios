//
//  AppClock.swift
//  Soulfull Gatherings
//
//  "Now", for anything on screen that changes with the date.
//
//  The day-unlock rule, Home's greeting and the streak are all worked out from
//  the time inside `body`, and a SwiftUI view only re-renders when something it
//  observes changes. The app spends most of its life suspended, so a member who
//  finished Day 1 at 9pm and came back from the app switcher the next morning
//  was still told "Day 2 opens tomorrow", greeted "Good evening", and shown a
//  streak that had already ended.
//
//  Reading the time through this clock makes each of those views depend on it.
//  `SoulfullGatheringsApp` ticks it when the scene becomes active and on the
//  system's significant time changes (midnight, a time-zone change), and every
//  view that read it renders again. `now` is always the real time, not the
//  time of the last tick.
//

import Foundation

@Observable @MainActor
final class AppClock {
    static let shared = AppClock()

    /// Bumped by `tick()`. Read by `now` so that reading the time registers a
    /// dependency on the next tick.
    private var generation = 0

    var now: Date {
        _ = generation
        return .now
    }

    /// The date may have moved under everything on screen: re-render whatever
    /// read `now`.
    func tick() { generation &+= 1 }
}
