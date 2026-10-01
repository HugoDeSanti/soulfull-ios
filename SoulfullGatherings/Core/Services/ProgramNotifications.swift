//
//  ProgramNotifications.swift
//  Soulfull Gatherings
//
//  The morning nudge: when a program day is finished, schedule a local
//  notification for the moment the next one is available.
//
//  Local only — no push server, no device tokens, nothing leaves the phone. The
//  unlock is computed from a date the app already holds, so there is nothing a
//  server could tell it that it doesn't know.
//
//  NOTE the gap between *opening* and *saying so*. A day opens at local
//  midnight, which is the rule; the notification fires at 08:00. Waking someone
//  at midnight to tell them they may now do yoga is a different decision from
//  the one about pacing, and the answer to it is no.
//

import Foundation
import UserNotifications

@MainActor
enum ProgramNotifications {

    /// Local hour the nudge fires on the day it unlocks.
    private static let hour = 8

    private static func identifier(programID: String, day: Int) -> String {
        "program-\(programID)-day-\(day)"
    }

    /// Asks for permission the first time a member joins a program — at the
    /// moment the nudge is worth something, not at launch when it reads as the
    /// app shaking them down for attention before earning any.
    ///
    /// A refusal is final and never re-asked: `notDetermined` is the only state
    /// this acts on, and everything downstream degrades to the in-app surface
    /// on Home.
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.data.info("Notification permission request failed: \(error.localizedDescription)")
        }
    }

    /// Schedules the nudge for one day of one program. Replaces any existing
    /// one with the same identifier, so re-running it is harmless.
    static func schedule(programID: String, programTitle: String,
                         day: Int, dayTitle: String, unlockAt: Date) {
        let calendar = Calendar.current
        guard let fireAt = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: unlockAt),
              fireAt > .now else {
            // The day is already open (or opens before this morning's hour).
            // Nothing to announce — they can see it now.
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Day \(day) is open"
        content.body = "\(dayTitle) — your next day of \(programTitle) is waiting."
        content.sound = .default
        content.userInfo = ["programID": programID, "day": day]

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
        let request = UNNotificationRequest(
            identifier: identifier(programID: programID, day: day),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.data.info("Couldn't schedule program nudge: \(error.localizedDescription)") }
        }
    }

    /// Drops every pending nudge for a program — on leaving it, or on sign-out.
    /// A notification for a program you are no longer in is the kind of thing
    /// people delete an app over.
    static func cancel(programID: String) {
        let center = UNUserNotificationCenter.current()
        let prefix = "program-\(programID)-day-"
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Drops one day's pending nudge — once that day is done. An early riser who
    /// finished Day 2 at 6:30 was still told at 8:00 that Day 2 was waiting.
    static func cancel(programID: String, day: Int) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(programID: programID, day: day)])
    }

    /// Drops every program nudge, whatever the program — used when the member
    /// signs out or deletes their account.
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("program-") }
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
