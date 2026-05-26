//
//  Models.swift
//  Soulfull Gatherings
//
//  Data models + mock content. All structs are value types, Identifiable,
//  and Hashable so they slot into NavigationStack value destinations.
//

import SwiftUI

// MARK: - Retreats (in-person)

struct Retreat: Identifiable, Hashable {
    let id: String
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

    /// Three-stop tone keyed by retreat id — see `Retreat.tones`.
    var tone: (top: Color, mid: Color, base: Color) { Retreat.tones[id] ?? Retreat.fallbackTone }

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

extension Retreat {
    static let mock: [Retreat] = {
        func d(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
        }
        return [
            Retreat(id: "mallorca",  name: "Mallorca",  country: "Spain",
                    startDate: d(4, 18),            endDate: d(4, 23),
                    maxGuests: 14, priceUsd: 4400,
                    tags: ["Hyrox", "Recovery", "Wellness"],
                    blurb: "Cliffside training mornings, cove swims, recovery rituals on the sand. Push and return.",
                    imageUrl: "retreat-mallorca"),
            Retreat(id: "kyoto",     name: "Kyoto",     country: "Japan",
                    startDate: d(5, 9),             endDate: d(5, 15),
                    maxGuests: 10, priceUsd: 6800,
                    tags: ["Meditation"],
                    blurb: "Temple to temple, walking. Tea ceremony every morning. Practice arriving where you already are.",
                    imageUrl: "retreat-kyoto"),
            Retreat(id: "sedona",    name: "Sedona",    country: "Arizona",
                    startDate: d(6, 6),             endDate: d(6, 11),
                    maxGuests: 12, priceUsd: 4200,
                    tags: ["Hiking", "Meditation"],
                    blurb: "Red rock canyon walks at sunrise. Vortex meditation. Stargazing on the mesa.",
                    imageUrl: "retreat-sedona"),
            Retreat(id: "chamonix",  name: "Chamonix",  country: "France",
                    startDate: d(2, 2, year: 2027), endDate: d(2, 7, year: 2027),
                    maxGuests: 12, priceUsd: 5400,
                    tags: ["Ski", "Yoga", "Wellness"],
                    blurb: "Powder mornings under Mont Blanc. Afternoon yoga in the chalet. Spa nights, cold plunge, repeat.",
                    imageUrl: "retreat-chamonix"),
            Retreat(id: "bali",      name: "Bali",      country: "Indonesia",
                    startDate: d(7, 14),            endDate: d(7, 20),
                    maxGuests: 14, priceUsd: 3900,
                    tags: ["Yoga", "Meditation"],
                    blurb: "Rice paddy mornings in Ubud. Twice-daily yoga, breathwork at dusk, jungle silence between.",
                    imageUrl: "retreat-bali"),
            Retreat(id: "lapland",   name: "Lapland",   country: "Finland",
                    startDate: d(1, 10, year: 2027), endDate: d(1, 15, year: 2027),
                    maxGuests: 10, priceUsd: 5800,
                    tags: ["Ski", "Yoga", "Wellness"],
                    blurb: "Aurora skies, sauna and ice plunge, forest skiing. The most still place we hold a circle.",
                    imageUrl: "retreat-lapland"),
            Retreat(id: "dolomites", name: "Dolomites", country: "Italy",
                    startDate: d(9, 8),             endDate: d(9, 13),
                    maxGuests: 12, priceUsd: 4600,
                    tags: ["Cycling", "Recovery", "Wellness"],
                    blurb: "Alpine passes by bike, recovery in the spa, long Italian dinners at altitude.",
                    imageUrl: "retreat-dolomites"),
        ]
    }()
}

// MARK: - Visual tones

extension Retreat {
    static let fallbackTone: (top: Color, mid: Color, base: Color) = (
        Color(red: 0.38, green: 0.48, blue: 0.62),
        Color(red: 0.18, green: 0.24, blue: 0.40),
        Color(red: 0.04, green: 0.06, blue: 0.16)
    )

    static let tones: [String: (top: Color, mid: Color, base: Color)] = [
        "mallorca":  (Color(red: 0.45, green: 0.62, blue: 0.65),
                      Color(red: 0.20, green: 0.32, blue: 0.40),
                      Color(red: 0.06, green: 0.10, blue: 0.14)),
        "kyoto":     (Color(red: 0.78, green: 0.40, blue: 0.22),
                      Color(red: 0.45, green: 0.22, blue: 0.13),
                      Color(red: 0.12, green: 0.06, blue: 0.05)),
        "sedona":    (Color(red: 0.80, green: 0.41, blue: 0.18),
                      Color(red: 0.48, green: 0.22, blue: 0.10),
                      Color(red: 0.13, green: 0.06, blue: 0.04)),
        "chamonix":  (Color(red: 0.60, green: 0.65, blue: 0.72),
                      Color(red: 0.30, green: 0.36, blue: 0.45),
                      Color(red: 0.10, green: 0.13, blue: 0.18)),
        "bali":      (Color(red: 0.28, green: 0.52, blue: 0.32),
                      Color(red: 0.14, green: 0.28, blue: 0.18),
                      Color(red: 0.04, green: 0.10, blue: 0.06)),
        "lapland":   (Color(red: 0.38, green: 0.48, blue: 0.62),
                      Color(red: 0.18, green: 0.24, blue: 0.40),
                      Color(red: 0.04, green: 0.06, blue: 0.16)),
        "dolomites": (Color(red: 0.42, green: 0.56, blue: 0.32),
                      Color(red: 0.20, green: 0.30, blue: 0.14),
                      Color(red: 0.07, green: 0.10, blue: 0.05)),
    ]
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
        Program(id: "cyc7",  title: "Cycling & Recovery",            lead: "Valentina Velasco",  when: "June 12–19",     days: 7,  imageUrl: "retreat-mallorca"),
        Program(id: "bw5",   title: "Intro to Breathwork",            lead: "Rodrigo Peán",       when: "June 24–28",     days: 5,  imageUrl: "retreat-bali"),
        Program(id: "yw14",  title: "Yoga & Wellness",                lead: "Alma Guerra",        when: "July 8–21",      days: 14, imageUrl: "retreat-dolomites"),
        Program(id: "hcl14", title: "Heal Yourself, Change Your Life",lead: "Michelle Campos",    when: "August 1–14",    days: 14, imageUrl: "retreat-sedona"),
        Program(id: "md7",   title: "Movement & Discipline",          lead: "Analu Chavez",       when: "July 14–20",     days: 7,  imageUrl: "retreat-kyoto")
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
        CommunityCircle(id: "wih",  title: "Women in Healing", host: "Mara Solé", attendees: 47, timeLabel: "Live now",   isLive: true),
        CommunityCircle(id: "mar",  title: "Men at Rest",      host: "Theo Park", attendees: 18, timeLabel: "In 25 min",  isLive: false)
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
        .init(id: "travel",  label: "travel & retreat",   isSubtle: false),
        .init(id: "heal",    label: "heal emotionally",    isSubtle: false),
        .init(id: "move",    label: "move my body",        isSubtle: false),
        .init(id: "connect", label: "find my community",   isSubtle: false),
        .init(id: "rest",    label: "rest & recover",      isSubtle: false),
        .init(id: "other",   label: "something else",      isSubtle: true)
    ]
}

struct BodyStateOption: Identifiable, Hashable {
    let id: String
    let label: String
    let isSubtle: Bool
}

extension BodyStateOption {
    static let all: [BodyStateOption] = [
        .init(id: "soft",    label: "soft & open",         isSubtle: false),
        .init(id: "tender",  label: "tender today",        isSubtle: false),
        .init(id: "anxious", label: "anxious or racing",   isSubtle: false),
        .init(id: "numb",    label: "numb or shut down",   isSubtle: false),
        .init(id: "tired",   label: "tired & depleted",    isSubtle: false),
        .init(id: "other",   label: "self-describe",       isSubtle: true)
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
        .init(id: "weekly", label: "weekly, when I need it")
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
        .init(id: "inspired",  label: "Inspired")
    ]
}
