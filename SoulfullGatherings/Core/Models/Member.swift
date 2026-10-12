//
//  Member.swift
//  Soulfull Gatherings
//
//  A member's own record: their profile row, and the rule their name is
//  held to.
//

import Foundation

// MARK: - User profile (Supabase `profiles` table)

/// One row per authenticated user (anonymous guest or permanent account).
/// Mirrors the `profiles` table: the row is created server-side by a trigger
/// and synced from the app via `SupabaseService.upsertProfile`/`fetchProfile`.
/// `stripeCustomerId` is read-only here — it is written by the Phase 2 Stripe
/// webhook, never by the client.
struct Profile: Identifiable, Hashable {
    let id: UUID
    var email: String
    var name: MemberName
    /// Nil until given: asked at email sign-up, offered on the You tab, never
    /// after Sign in with Apple. Private to the member (0033).
    var birthDate: BirthDate? = nil
    var intentions: [String]
    var bodyState: String
    var frequency: String
    var stripeCustomerId: String?
    /// `avatars/<user id>/<uuid>.jpg` in Storage, or nil for no photo. Written
    /// by `SupabaseService.setAvatar`, never by `upsertProfile`.
    var avatarUrl: String? = nil
    /// Whether finished practices appear in the Community feed. Opt-out,
    /// on the You tab. Never touched by `upsertProfile`.
    var shareActivity: Bool = true
}

/// A member's name, as they gave it: the name they go by and their last name,
/// as `profiles.first_name` / `last_name` hold them (0033). The server keeps
/// `full_name` as a copy of the two on one line, for everything that reads a
/// whole name (search, a guide named by their account, Stripe).
///
/// Together they hold to 64 characters, the limit `profiles.full_name` and
/// `instructors.name` have (0030). Names reach every member through the feed,
/// and a guide's through every page they made, so they need a ceiling.
///
/// Counted the way Postgres's `char_length` counts, in Unicode code points,
/// but cut only between characters: an accent or an emoji is never split, and
/// a name that fits here is never refused there.
struct MemberName: Hashable, Sendable {
    var first: String
    var last: String

    static let maxLength = 64

    init(first: String = "", last: String = "") {
        self.first = first
        self.last = last
    }

    /// A name that arrives on one line (this phone's copy from before the
    /// name came in parts, an older build's sign-up), split at the first
    /// space as 0033 split the names already stored: "Hugo De Santiago" is
    /// "Hugo" and "De Santiago".
    init(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gap = trimmed.firstIndex(where: \.isWhitespace) else {
            self.init(first: trimmed)
            return
        }
        self.init(first: String(trimmed[..<gap]),
                  last: trimmed[gap...].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// What is stored, as the server stores it (0033): each part trimmed, a
    /// last name alone moved to first (it's the name they go by), and the two
    /// cut to 64 together, the first name first.
    var limited: MemberName {
        var first = Self.limited(first)
        var last = Self.limited(last)
        if first.isEmpty { (first, last) = (last, "") }
        let room = Self.maxLength - first.unicodeScalars.count - 1
        last = room > 0 ? Self.limited(Self.capped(last, to: room)) : ""
        return MemberName(first: first, last: last)
    }

    /// On one line, as `profiles.full_name` holds it: "Hugo De Santiago".
    var full: String {
        let name = limited
        return name.last.isEmpty ? name.first : "\(name.first) \(name.last)"
    }

    /// No name at all: an Apple account that shared none, or a guest who
    /// hasn't given one.
    var isEmpty: Bool { limited.first.isEmpty }

    /// Both parts given, which an account's name needs.
    var isComplete: Bool {
        !Self.limited(first).isEmpty && !Self.limited(last).isEmpty
    }

    /// How other members see the name in Community, the way the server's
    /// `community_display_name(first, last)` shortens it: the first name and
    /// the last name's initial ("Mary Ann S."), a first name alone as it is.
    /// Nil for no name. (The server also hides an objectionable name, which
    /// this doesn't try to know.)
    var shownInCommunity: String? {
        let name = limited
        guard !name.first.isEmpty else { return nil }
        guard let initial = name.last.first else { return name.first }
        return "\(name.first) \(String(initial).uppercased())."
    }

    /// Keeps each part this name has, and takes `other`'s for a part it
    /// lacks: the first name onboarding asked for, with the last name Apple
    /// shared.
    func filled(from other: MemberName) -> MemberName {
        MemberName(first: Self.limited(first).isEmpty ? other.first : first,
                   last: Self.limited(last).isEmpty ? other.last : last).limited
    }

    /// For a text field: cut to the limit as it is typed, spaces kept (one
    /// between two words is part of the name).
    static func capped(_ text: String, to limit: Int = maxLength) -> String {
        var scalars = 0
        for index in text.indices {
            scalars += text[index].unicodeScalars.count
            if scalars > limit { return String(text[..<index]) }
        }
        return text
    }

    /// One part as it is stored: trimmed, then cut to the limit.
    static func limited(_ name: String) -> String {
        capped(name.trimmingCharacters(in: .whitespacesAndNewlines))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A member's date of birth: a calendar day, not a moment
/// (`profiles.date_of_birth`, a Postgres `date`). Written as `yyyy-MM-dd` in
/// the Gregorian calendar whatever the device's own, and read in the time zone
/// the picker showed it in, so nobody's birthday moves a day for being far
/// from Greenwich (the retreat form once sent the day before).
struct BirthDate: Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    /// The youngest a member can be: the Terms' minimum age, and the App
    /// Store's 13+. The server holds the same line (0033).
    static let minimumAge = 13

    /// The day `date` falls on where it was picked.
    init(_ date: Date, in timeZone: TimeZone = .current) {
        let parts = Self.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        self.year = parts.year ?? 1900
        self.month = parts.month ?? 1
        self.day = parts.day ?? 1
    }

    /// `yyyy-MM-dd`, as Postgres writes a `date`; nil for anything else,
    /// including a day that doesn't exist.
    init?(dayString: String) {
        let parts = dayString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let calendar = Self.calendar(TimeZone(identifier: "UTC")!)
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard components.isValidDate(in: calendar) else { return nil }
        (year, month, day) = (parts[0], parts[1], parts[2])
    }

    var dayString: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Noon on that day where it's shown, for a date picker.
    func date(in timeZone: TimeZone = .current) -> Date {
        Self.calendar(timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    /// The latest date of birth a member can have on `now`: `minimumAge`
    /// years ago. The wheel stops there, so a younger date can't be picked
    /// rather than being refused after the fact.
    static func latest(now: Date, in timeZone: TimeZone = .current) -> Date {
        calendar(timeZone).date(byAdding: .year, value: -minimumAge, to: now) ?? now
    }

    /// The earliest the wheel goes, and the server takes.
    static func earliest(in timeZone: TimeZone = .current) -> Date {
        BirthDate(dayString: "1900-01-01")!.date(in: timeZone)
    }

    /// Where the wheel opens: old enough to be plausible, not so old that
    /// most people scroll the wrong way (the retreat form's choice).
    static func wheelStart(now: Date, in timeZone: TimeZone = .current) -> Date {
        calendar(timeZone).date(byAdding: .year, value: -32, to: now) ?? now
    }

    /// "12 March 1990", in the member's own format.
    var formatted: String { date().formatted(date: .long, time: .omitted) }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
