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
    let when: String
    let days: Int
    let guests: Int
    let price: String
    let tag: String
    let blurb: String
    /// Asset catalog name for the full-bleed photo.
    let image: String
    /// Three-stop tone used for the warm corner glow on the stack view.
    let tone: (top: Color, mid: Color, base: Color)

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Retreat, rhs: Retreat) -> Bool { lhs.id == rhs.id }
}

extension Retreat {
    static let mock: [Retreat] = [
        Retreat(
            id: "mallorca", name: "Mallorca", country: "Spain",
            when: "April 18–23", days: 5, guests: 14, price: "$4,400",
            tag: "Hyrox · Recovery · Wellness",
            blurb: "Cliffside training mornings, cove swims, recovery rituals on the sand. Push and return.",
            image: "retreat-mallorca",
            tone: (Color(red: 0.45, green: 0.62, blue: 0.65),
                   Color(red: 0.20, green: 0.32, blue: 0.40),
                   Color(red: 0.06, green: 0.10, blue: 0.14))
        ),
        Retreat(
            id: "kyoto", name: "Kyoto", country: "Japan",
            when: "May 9–15", days: 6, guests: 10, price: "$6,800",
            tag: "Meditation",
            blurb: "Temple to temple, walking. Tea ceremony every morning. Practice arriving where you already are.",
            image: "retreat-kyoto",
            tone: (Color(red: 0.78, green: 0.40, blue: 0.22),
                   Color(red: 0.45, green: 0.22, blue: 0.13),
                   Color(red: 0.12, green: 0.06, blue: 0.05))
        ),
        Retreat(
            id: "sedona", name: "Sedona", country: "Arizona",
            when: "June 6–11", days: 5, guests: 12, price: "$4,200",
            tag: "Hiking · Meditation",
            blurb: "Red rock canyon walks at sunrise. Vortex meditation. Stargazing on the mesa.",
            image: "retreat-sedona",
            tone: (Color(red: 0.80, green: 0.41, blue: 0.18),
                   Color(red: 0.48, green: 0.22, blue: 0.10),
                   Color(red: 0.13, green: 0.06, blue: 0.04))
        ),
        Retreat(
            id: "chamonix", name: "Chamonix", country: "France",
            when: "February 2–7", days: 5, guests: 12, price: "$5,400",
            tag: "Ski · Yoga · Wellness",
            blurb: "Powder mornings under Mont Blanc. Afternoon yoga in the chalet. Spa nights, cold plunge, repeat.",
            image: "retreat-chamonix",
            tone: (Color(red: 0.60, green: 0.65, blue: 0.72),
                   Color(red: 0.30, green: 0.36, blue: 0.45),
                   Color(red: 0.10, green: 0.13, blue: 0.18))
        ),
        Retreat(
            id: "bali", name: "Bali", country: "Indonesia",
            when: "July 14–20", days: 6, guests: 14, price: "$3,900",
            tag: "Yoga · Meditation",
            blurb: "Rice paddy mornings in Ubud. Twice-daily yoga, breathwork at dusk, jungle silence between.",
            image: "retreat-bali",
            tone: (Color(red: 0.28, green: 0.52, blue: 0.32),
                   Color(red: 0.14, green: 0.28, blue: 0.18),
                   Color(red: 0.04, green: 0.10, blue: 0.06))
        ),
        Retreat(
            id: "lapland", name: "Lapland", country: "Finland",
            when: "January 10–15", days: 5, guests: 10, price: "$5,800",
            tag: "Ski · Yoga · Wellness",
            blurb: "Aurora skies, sauna and ice plunge, forest skiing. The most still place we hold a circle.",
            image: "retreat-lapland",
            tone: (Color(red: 0.38, green: 0.48, blue: 0.62),
                   Color(red: 0.18, green: 0.24, blue: 0.40),
                   Color(red: 0.04, green: 0.06, blue: 0.16))
        ),
        Retreat(
            id: "dolomites", name: "Dolomites", country: "Italy",
            when: "September 8–13", days: 5, guests: 12, price: "$4,600",
            tag: "Cycling · Recovery · Wellness",
            blurb: "Alpine passes by bike, recovery in the spa, long Italian dinners at altitude.",
            image: "retreat-dolomites",
            tone: (Color(red: 0.42, green: 0.56, blue: 0.32),
                   Color(red: 0.20, green: 0.30, blue: 0.14),
                   Color(red: 0.07, green: 0.10, blue: 0.05))
        )
    ]
}

// MARK: - Digital programs (for home carousel)

struct Program: Identifiable, Hashable {
    let id: String
    let title: String
    let lead: String
    let when: String
    let days: Int
    let image: String
}

extension Program {
    static let mock: [Program] = [
        Program(id: "cyc7",  title: "Cycling & Recovery",            lead: "Valentina Velasco",  when: "June 12–19",     days: 7,  image: "retreat-mallorca"),
        Program(id: "bw5",   title: "Intro to Breathwork",            lead: "Rodrigo Peán",       when: "June 24–28",     days: 5,  image: "retreat-bali"),
        Program(id: "yw14",  title: "Yoga & Wellness",                lead: "Alma Guerra",        when: "July 8–21",      days: 14, image: "retreat-dolomites"),
        Program(id: "hcl14", title: "Heal Yourself, Change Your Life",lead: "Michelle Campos",    when: "August 1–14",    days: 14, image: "retreat-sedona"),
        Program(id: "md7",   title: "Movement & Discipline",          lead: "Analu Chavez",       when: "July 14–20",     days: 7,  image: "retreat-kyoto")
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
