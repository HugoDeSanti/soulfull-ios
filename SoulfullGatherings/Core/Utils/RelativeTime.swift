//
//  RelativeTime.swift
//  Soulfull Gatherings
//
//  When something happened, the way the Community tab and a practice's
//  comments say it: "just now", "12 min ago", "3 hr ago", "yesterday",
//  "Monday", "12 Sep".
//

import Foundation

enum RelativeTime {
    /// Time is an argument, so a test can pin it; screens pass
    /// `AppClock.shared.now` (or `.now` where a line re-renders on its own).
    /// A moment a little after `now` — a server's clock running ahead of the
    /// phone's — is "just now".
    static func label(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600)) hr ago" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "yesterday" }
        var style = Date.FormatStyle.dateTime
        style.timeZone = calendar.timeZone
        if days < 7 { return date.formatted(style.weekday(.wide)) }
        return date.formatted(style.day().month(.abbreviated))
    }
}
