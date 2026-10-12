//
//  Fixtures.swift
//  Soulfull Gatherings
//
//  Sample content for SwiftUI previews and the DEBUG `-preview-*` screens,
//  compiled out of Release, so no build that ships can show it. Nothing here
//  is ever a fallback for a read that failed (see `RetreatsLoadFailure`):
//  sample content shown as real is Guideline 2.1(a) temporary content. Some
//  names here belong to real people (CLAUDE.md, Open items), so never take a
//  guide's name from these.
//

#if DEBUG
import SwiftUI

extension Retreat {
    private static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// Sample retreats. Their dates are absolute and will rot, which is fine
    /// for a preview. They carry no `experience` (the brochure is the
    /// `retreats.experience` column), so they render the concise layout.
    static let mock: [Retreat] = [
        Retreat(id: 1, name: "Mallorca", country: "Spain",
                startDate: day(2027, 7, 21), endDate: day(2027, 7, 26),
                maxGuests: 14, priceUsd: 4400,
                tags: ["Wellness", "Fitness", "Recovery"],
                blurb: "A private Mediterranean villa, curated company, and days built to move, explore, recover, and connect.",
                imageUrl: "retreat-images/mallorca-2027-07.jpg",
                toneTop: Color(hex: "#73A0B8"), toneMid: Color(hex: "#335266"), toneBase: Color(hex: "#0F1A24"),
                // No invite: a real one comes from `retreats.group_chat_url`,
                // and the hub draws its tile only when there is one.
                groupChatURL: nil),
        Retreat(id: 2, name: "Bali", country: "Indonesia",
                startDate: day(2027, 8, 9), endDate: day(2027, 8, 16),
                maxGuests: 16, priceUsd: 3900,
                tags: ["Breathwork", "Somatic", "Jungle"],
                blurb: "Seven nights between rice terraces and temple mornings. Breath, stillness, and green without end.",
                imageUrl: "retreat-images/bali-2026-07.jpg",
                toneTop: Color(hex: "#9DBA6E"), toneMid: Color(hex: "#4C6B33"), toneBase: Color(hex: "#15200D")),
        Retreat(id: 3, name: "Dolomites", country: "Italy",
                startDate: day(2027, 9, 8), endDate: day(2027, 9, 13),
                maxGuests: 12, priceUsd: 5200,
                tags: ["Alpine", "Hiking", "Cold Therapy"],
                blurb: "Granite light, long ridgelines, and evenings that ask very little of you. Walk up, settle down.",
                imageUrl: "retreat-images/dolomites-2027-09.jpg",
                toneTop: Color(hex: "#B9C3CD"), toneMid: Color(hex: "#5C6B7A"), toneBase: Color(hex: "#161B21")),
        Retreat(id: 4, name: "Kyoto", country: "Japan",
                startDate: day(2027, 10, 12), endDate: day(2027, 10, 18),
                maxGuests: 10, priceUsd: 6100,
                tags: ["Zen", "Tea", "Forest Bathing"],
                blurb: "Temple gardens at first light, tea in silence, maple shade. A week of deliberate slowness.",
                imageUrl: "retreat-images/kyoto-2026-05.jpg",
                toneTop: Color(hex: "#C98A66"), toneMid: Color(hex: "#7A4631"), toneBase: Color(hex: "#1F120C")),
        Retreat(id: 5, name: "Sedona", country: "United States",
                startDate: day(2027, 11, 6), endDate: day(2027, 11, 11),
                maxGuests: 14, priceUsd: 4800,
                tags: ["Desert", "Sound Healing", "Hiking"],
                blurb: "Red rock amphitheaters, canyon hikes, sound baths under enormous sky.",
                imageUrl: "retreat-images/sedona-2026-06.jpg",
                toneTop: Color(hex: "#D88E5E"), toneMid: Color(hex: "#8C4A2D"), toneBase: Color(hex: "#23120A")),
        Retreat(id: 6, name: "Chamonix", country: "France",
                startDate: day(2027, 1, 15), endDate: day(2027, 1, 20),
                maxGuests: 12, priceUsd: 5600,
                tags: ["Snow", "Sauna", "Breathwork"],
                blurb: "Mont Blanc out every window. Powder mornings, sauna and plunge, fireside circles.",
                imageUrl: "retreat-images/chamonix-2027-02.jpg",
                toneTop: Color(hex: "#A9C3DD"), toneMid: Color(hex: "#4F6B85"), toneBase: Color(hex: "#101822")),
        Retreat(id: 7, name: "Lapland", country: "Finland",
                startDate: day(2027, 2, 19), endDate: day(2027, 2, 24),
                maxGuests: 10, priceUsd: 5900,
                tags: ["Aurora", "Ice Bath", "Silence"],
                blurb: "Northern lights over frozen lakes. Ice, heat, and the deepest quiet you've ever heard.",
                imageUrl: "retreat-images/lapland-2027-01.jpg",
                toneTop: Color(hex: "#6FA08F"), toneMid: Color(hex: "#2E5247"), toneBase: Color(hex: "#0C1714")),
    ]
}

extension Program {
    /// Preview / DEBUG fixture only — never a fallback for the live catalog.
    /// See `RetreatsLoadFailure` for why an invented catalogue must not stand
    /// in for a failed fetch.
    static let mock: [Program] = [
        Program(id: "finding-ground", title: "Finding Ground", lead: "Alma Guerra",
                days: 7, imageUrl: "retreat-images/dolomites-2027-09.jpg",
                blurb: "Seven days of returning to the body — breath, movement, reflection and food, one day at a time.",
                curriculum: ProgramCurriculum(
                    overview: "A week of small, repeatable returns. Each day asks for twenty minutes and gives back a little more room than you had.",
                    days: [
                        ProgramDay(day: 1, title: "Arriving", intention: "Land before you ask anything of the body.",
                                   imageUrl: "retreat-images/dolomites-2027-09.jpg",
                                   activities: [.init(kind: .journal, contentID: 1, note: "Answer from sensation, not from thought."),
                                                .init(kind: .exercise, contentID: 1)]),
                        ProgramDay(day: 2, title: "Steadiness", intention: "Find the floor. Everything else is built on it.",
                                   imageUrl: "retreat-images/sedona-2026-06.jpg",
                                   activities: [.init(kind: .exercise, contentID: 4, note: "Slow is the whole instruction."),
                                                .init(kind: .recipe, contentID: 1)]),
                        ProgramDay(day: 3, title: "Letting go", intention: "Set down one thing you have been carrying out of habit.",
                                   imageUrl: "retreat-images/kyoto-2026-05.jpg",
                                   activities: [.init(kind: .journal, contentID: 2),
                                                .init(kind: .exercise, contentID: 3)]),
                    ],
                    closing: ProgramClosing(title: "You have come back seven times",
                                            body: "That is the practice — not the week, but the returning.")),
                instructorID: "alma-guerra"),
    ]
}

extension PracticeSession {
    /// Shape-only fixtures for SwiftUI previews.
    ///
    /// These used to carry public sample media (a stock MP3 and Big Buck Bunny)
    /// and were the runtime fallback whenever `practice_sessions` was unseeded —
    /// which meant a shipping build played a cartoon rabbit as a guided
    /// meditation. `storagePath` is now empty and nothing in the app reads these
    /// at runtime: `PracticeViewModel` reports an unseeded track as empty and
    /// `PracticeView` renders it as "Coming soon".
    ///
    /// Real rows carry a bucket-relative `storagePath` resolved via a signed URL.
    static let mock: [PracticeSession] = [
        // Somatic Exercises
        .init(id: 1, category: .somatic, title: "Grounding Body Scan", lead: "Dr. Anya Iyer", mediaKind: .audio, storagePath: "", durationSeconds: 720, imageUrl: "retreat-images/sedona-2026-06.jpg", blurb: "A slow head-to-toe scan to settle the nervous system."),
        .init(id: 2, category: .somatic, title: "Shake & Release", lead: "Mara Solé", mediaKind: .audio, storagePath: "", durationSeconds: 480, imageUrl: "retreat-images/mallorca-2027-07.jpg", blurb: "Discharge held tension through gentle, guided movement."),
        .init(id: 3, category: .somatic, title: "Orienting to Safety", lead: "Theo Park", mediaKind: .video, storagePath: "", durationSeconds: 900, imageUrl: "retreat-images/dolomites-2027-09.jpg", blurb: "A trauma-informed practice for re-establishing felt safety."),

        // Breathwork
        .init(id: 4, category: .breathwork, title: "Box Breathing Basics", lead: "Rodrigo Peán", mediaKind: .audio, storagePath: "", durationSeconds: 360, imageUrl: "retreat-images/bali-2026-07.jpg", blurb: "Four-count breathing to steady a racing mind."),
        .init(id: 5, category: .breathwork, title: "Coherent Breathing", lead: "Valentina Velasco", mediaKind: .audio, storagePath: "", durationSeconds: 600, imageUrl: "retreat-images/mallorca-2027-07.jpg", blurb: "Five breaths a minute to balance the autonomic system."),
        .init(id: 6, category: .breathwork, title: "Breath of Fire", lead: "Alma Guerra", mediaKind: .video, storagePath: "", durationSeconds: 540, imageUrl: "retreat-images/kyoto-2026-05.jpg", blurb: "An energizing kundalini practice to wake the body."),

        // Meditation
        .init(id: 7, category: .meditation, title: "Morning Stillness", lead: "Michelle Campos", mediaKind: .audio, storagePath: "", durationSeconds: 600, imageUrl: "retreat-images/kyoto-2026-05.jpg", blurb: "Begin the day with ten minutes of open awareness."),
        .init(id: 8, category: .meditation, title: "Sleep Descent", lead: "Analu Chavez", mediaKind: .audio, storagePath: "", durationSeconds: 1200, imageUrl: "retreat-images/dolomites-2027-09.jpg", blurb: "A long, drifting body relaxation for falling asleep."),
        .init(id: 9, category: .meditation, title: "Loving-Kindness", lead: "Mara Solé", mediaKind: .audio, storagePath: "", durationSeconds: 840, imageUrl: "retreat-images/sedona-2026-06.jpg", blurb: "Cultivate warmth toward yourself and others."),
    ]

    static func mock(for category: PracticeCategory) -> [PracticeSession] {
        mock.filter { $0.category == category }
    }
}

extension JournalPrompt {
    /// Preview / DEBUG fixture only. Id 3 is the prompt `-preview-instructors`
    /// credits to its second guide.
    static let mock: [JournalPrompt] = [
        .init(id: 1, title: "What is your body asking for today?", prompt: "Close your eyes for a breath and scan from head to toe. Without fixing anything, name what you notice.", theme: "Embodiment", imageUrl: "retreat-images/dolomites-2027-09.jpg"),
        .init(id: 3, title: "Where did you feel ease this week?", prompt: "Recall a moment — however small — when your shoulders dropped and time softened. Describe it in detail.", theme: "Gratitude", imageUrl: "retreat-images/bali-2026-07.jpg"),
    ]
}

extension Exercise {
    /// Preview / DEBUG fixture only. Id 1 is the sequence `-preview-instructors`
    /// credits to its first guide.
    static let mock: [Exercise] = [
        .init(id: 1, title: "Morning Mobility Flow", focus: "Mobility", durationSeconds: 600, imageUrl: "retreat-images/mallorca-2027-07.jpg", blurb: "A gentle full-body sequence to wake the joints and spine.", steps: [
            .init(id: 1, name: "Cat–Cow", detail: "8 slow reps"),
            .init(id: 2, name: "World's Greatest Stretch", detail: "5 reps each side"),
            .init(id: 3, name: "Hip Circles", detail: "10 each direction"),
        ]),
        .init(id: 5, title: "Evening Yin", focus: "Yoga", durationSeconds: 1200, imageUrl: "retreat-images/kyoto-2026-05.jpg", blurb: "Long, supported holds for the end of the day.", steps: [
            .init(id: 1, name: "Butterfly", detail: "Hold 3 min"),
            .init(id: 2, name: "Savasana", detail: nil),
        ]),
    ]
}

extension Recipe {
    /// Preview / DEBUG fixture only. Id 1 is the recipe `-preview-instructors`
    /// credits to its first guide.
    static let mock: [Recipe] = [
        .init(id: 1, title: "Golden Turmeric Lentils", angle: "Anti-inflammatory", minutes: 35, servings: 4, imageUrl: "retreat-images/bali-2026-07.jpg", blurb: "A warming, grounding bowl built on turmeric, ginger, and red lentils.",
              ingredients: ["1 cup red lentils", "1 onion, diced", "2 tsp turmeric", "1 can coconut milk"],
              steps: ["Sauté the onion until soft.", "Stir in the turmeric, then the lentils and coconut milk.", "Simmer until tender."]),
    ]
}

extension WrittenLibrary {
    static let mock = WrittenLibrary(journals: JournalPrompt.mock,
                                     exercises: Exercise.mock,
                                     recipes: Recipe.mock)
}
#endif
