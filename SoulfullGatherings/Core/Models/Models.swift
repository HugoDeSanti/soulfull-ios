//
//  Models.swift
//  Soulfull Gatherings
//
//  Data models. All structs are value types, Identifiable, and Hashable so
//  they slot into NavigationStack value destinations.
//

import SwiftUI

// MARK: - Retreats (in-person)

struct Retreat: Identifiable, Hashable {
    let id: Int
    let name: String
    let country: String
    let startDate: Date
    let endDate: Date
    let maxGuests: Int
    let priceUsd: Int
    let tags: [String]
    let blurb: String
    /// Asset catalog name (current) or Supabase Storage URL (future).
    let imageUrl: String
    /// Visual tone sourced from the DB; used for backdrop color grading.
    let toneTop: Color
    let toneMid: Color
    let toneBase: Color

    var tone: (top: Color, mid: Color, base: Color) { (toneTop, toneMid, toneBase) }

    /// Formatted date range for display, e.g. "April 18–23" or "Jan 10–Feb 3".
    var when: String {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        if cal.component(.month, from: startDate) == cal.component(.month, from: endDate) {
            fmt.dateFormat = "MMMM d"
            let start = fmt.string(from: startDate)
            fmt.dateFormat = "d"
            return "\(start)–\(fmt.string(from: endDate))"
        } else {
            fmt.dateFormat = "MMM d"
            return "\(fmt.string(from: startDate))–\(fmt.string(from: endDate))"
        }
    }

    var durationDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }

    var priceFormatted: String {
        priceUsd.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Retreat, rhs: Retreat) -> Bool { lhs.id == rhs.id }
}

// MARK: - Digital programs (for home carousel)

struct Program: Identifiable, Hashable {
    let id: String
    let title: String
    let lead: String
    let when: String
    let days: Int
    let imageUrl: String
}

extension Program {
    static let mock: [Program] = [
        Program(id: "cyc7",  title: "Cycling & Recovery",             lead: "Valentina Velasco", when: "June 12–19",  days: 7,  imageUrl: "retreat-mallorca"),
        Program(id: "bw5",   title: "Intro to Breathwork",            lead: "Rodrigo Peán",      when: "June 24–28",  days: 5,  imageUrl: "retreat-bali"),
        Program(id: "yw14",  title: "Yoga & Wellness",                lead: "Alma Guerra",        when: "July 8–21",   days: 14, imageUrl: "retreat-dolomites"),
        Program(id: "hcl14", title: "Heal Yourself, Change Your Life", lead: "Michelle Campos",   when: "August 1–14", days: 14, imageUrl: "retreat-sedona"),
        Program(id: "md7",   title: "Movement & Discipline",          lead: "Analu Chavez",       when: "July 14–20",  days: 7,  imageUrl: "retreat-kyoto"),
    ]
}

// MARK: - Circles (live now)

struct CommunityCircle: Identifiable, Hashable {
    let id: String
    let title: String
    let host: String
    let attendees: Int
    let timeLabel: String
    let isLive: Bool
}

extension CommunityCircle {
    static let mock: [CommunityCircle] = [
        CommunityCircle(id: "wih", title: "Women in Healing", host: "Mara Solé", attendees: 47, timeLabel: "Live now",  isLive: true),
        CommunityCircle(id: "mar", title: "Men at Rest",      host: "Theo Park", attendees: 18, timeLabel: "In 25 min", isLive: false),
    ]
}

// MARK: - Onboarding choices

struct IntentionOption: Identifiable, Hashable {
    let id: String
    let label: String
    let isSubtle: Bool
}

extension IntentionOption {
    static let all: [IntentionOption] = [
        .init(id: "travel",  label: "travel & retreat",  isSubtle: false),
        .init(id: "heal",    label: "heal emotionally",   isSubtle: false),
        .init(id: "move",    label: "move my body",       isSubtle: false),
        .init(id: "connect", label: "find my community",  isSubtle: false),
        .init(id: "rest",    label: "rest & recover",     isSubtle: false),
        .init(id: "other",   label: "something else",     isSubtle: true),
    ]
}

struct BodyStateOption: Identifiable, Hashable {
    let id: String
    let label: String
    let isSubtle: Bool
}

extension BodyStateOption {
    static let all: [BodyStateOption] = [
        .init(id: "soft",    label: "soft & open",       isSubtle: false),
        .init(id: "tender",  label: "tender today",       isSubtle: false),
        .init(id: "anxious", label: "anxious or racing",  isSubtle: false),
        .init(id: "numb",    label: "numb or shut down",  isSubtle: false),
        .init(id: "tired",   label: "tired & depleted",   isSubtle: false),
        .init(id: "other",   label: "self-describe",      isSubtle: true),
    ]
}

struct FrequencyOption: Identifiable, Hashable {
    let id: String
    let label: String
}

extension FrequencyOption {
    static let all: [FrequencyOption] = [
        .init(id: "daily",  label: "every day"),
        .init(id: "most",   label: "most days"),
        .init(id: "few",    label: "a few times a week"),
        .init(id: "weekly", label: "weekly, when I need it"),
    ]
}

// MARK: - Mood chips on Home

struct MoodChip: Identifiable, Hashable {
    let id: String
    let label: String
}

extension MoodChip {
    static let all: [MoodChip] = [
        .init(id: "anxious",   label: "Anxious"),
        .init(id: "grateful",  label: "Grateful"),
        .init(id: "tired",     label: "Tired"),
        .init(id: "joyful",    label: "Joyful"),
        .init(id: "tender",    label: "Tender"),
        .init(id: "calm",      label: "Calm"),
        .init(id: "lost",      label: "Lost"),
        .init(id: "hopeful",   label: "Hopeful"),
        .init(id: "sad",       label: "Sad"),
        .init(id: "peaceful",  label: "Peaceful"),
        .init(id: "angry",     label: "Angry"),
        .init(id: "inspired",  label: "Inspired"),
    ]
}
