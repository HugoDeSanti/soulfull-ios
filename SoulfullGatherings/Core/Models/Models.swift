//
//  Models.swift
//  Soulfull Gatherings
//
//  Data models. All structs are value types, Identifiable, and Hashable so
//  they slot into NavigationStack value destinations.
//

import SwiftUI

// MARK: - User profile (Supabase `profiles` table)

/// One row per authenticated user (anonymous guest or permanent account).
/// Mirrors the `profiles` table: the row is created server-side by a trigger
/// and synced from the app via `SupabaseService.upsertProfile`/`fetchProfile`.
/// `stripeCustomerId` is read-only here — it is written by the Phase 2 Stripe
/// webhook, never by the client.
struct Profile: Identifiable, Hashable {
    let id: UUID
    var email: String
    var fullName: String
    var intentions: [String]
    var bodyState: String
    var frequency: String
    var stripeCustomerId: String?
}

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

// MARK: - Practices (on-demand audio / video library)

/// The three tracks surfaced on the Practice tab. `rawValue` matches the
/// `category` column in the `practice_sessions` Supabase table.
enum PracticeCategory: String, Identifiable, Hashable, CaseIterable {
    case somatic, breathwork, meditation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .somatic:    return "Somatic Therapy"
        case .breathwork: return "Breathwork"
        case .meditation: return "Meditation"
        }
    }

    var blurb: String {
        switch self {
        case .somatic:    return "Release what the body holds. Gentle, guided work for the nervous system."
        case .breathwork: return "Shift your state through the breath. Active and restorative patterns."
        case .meditation: return "Stillness, on demand. Guided sits for focus, sleep, and calm."
        }
    }

    var systemImage: String {
        switch self {
        case .somatic:    return "figure.mind.and.body"
        case .breathwork: return "wind"
        case .meditation: return "moon.stars"
        }
    }

    /// Backdrop asset (placeholder reuse until category art is added).
    var imageName: String {
        switch self {
        case .somatic:    return "practice-somatic"
        case .breathwork: return "practice-breathwork"
        case .meditation: return "practice-meditation"
        }
    }
}

/// Whether a session plays as audio-only or full video. Maps to the
/// `media_kind` column.
enum MediaKind: String, Hashable {
    case audio, video

    var label: String { self == .audio ? "Audio" : "Video" }
    var systemImage: String { self == .audio ? "waveform" : "play.rectangle.fill" }
}

/// A playable piece of media, decoupled from the content type that owns it, so
/// `PracticePlayerView` can serve sessions and massages alike.
struct MediaItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let lead: String
    let imageUrl: String
    let mediaKind: MediaKind
    /// Storage object path, or an absolute `http(s)` URL for sample / public media.
    let storagePath: String
    let durationSeconds: Int

    var durationLabel: String {
        let minutes = max(0, durationSeconds) / 60
        return minutes == 0 ? "\(durationSeconds) sec" : "\(minutes) min"
    }
}

struct PracticeSession: Identifiable, Hashable {
    let id: Int
    let category: PracticeCategory
    let title: String
    /// Instructor / guide.
    let lead: String
    let mediaKind: MediaKind
    /// Supabase Storage object path (e.g. "somatic/grounding-scan.m4a"), or an
    /// absolute `http(s)` URL for externally-hosted / sample media.
    let storagePath: String
    let durationSeconds: Int
    /// Asset catalog name (current) or Storage URL (future).
    let imageUrl: String
    let blurb: String

    var durationLabel: String {
        let minutes = max(0, durationSeconds) / 60
        return minutes == 0 ? "\(durationSeconds) sec" : "\(minutes) min"
    }

    var media: MediaItem {
        MediaItem(id: id, title: title, lead: lead, imageUrl: imageUrl,
                  mediaKind: mediaKind, storagePath: storagePath, durationSeconds: durationSeconds)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: PracticeSession, rhs: PracticeSession) -> Bool { lhs.id == rhs.id }
}

extension PracticeSession {
    /// Public sample media so the player works end-to-end before the
    /// `practice_sessions` table / Storage bucket are seeded. Real rows carry a
    /// bucket-relative `storagePath` instead and resolve via a signed URL.
    private static let sampleAudio = "https://download.samplelib.com/mp3/sample-15s.mp3"
    private static let sampleVideo = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"

    static let mock: [PracticeSession] = [
        // Somatic Therapy
        .init(id: 1, category: .somatic, title: "Grounding Body Scan", lead: "Dr. Anya Iyer", mediaKind: .audio, storagePath: sampleAudio, durationSeconds: 720, imageUrl: "retreat-sedona", blurb: "A slow head-to-toe scan to settle the nervous system."),
        .init(id: 2, category: .somatic, title: "Shake & Release", lead: "Mara Solé", mediaKind: .audio, storagePath: sampleAudio, durationSeconds: 480, imageUrl: "retreat-mallorca", blurb: "Discharge held tension through gentle, guided movement."),
        .init(id: 3, category: .somatic, title: "Orienting to Safety", lead: "Theo Park", mediaKind: .video, storagePath: sampleVideo, durationSeconds: 900, imageUrl: "retreat-dolomites", blurb: "A trauma-informed practice for re-establishing felt safety."),

        // Breathwork
        .init(id: 4, category: .breathwork, title: "Box Breathing Basics", lead: "Rodrigo Peán", mediaKind: .audio, storagePath: sampleAudio, durationSeconds: 360, imageUrl: "retreat-bali", blurb: "Four-count breathing to steady a racing mind."),
        .init(id: 5, category: .breathwork, title: "Coherent Breathing", lead: "Valentina Velasco", mediaKind: .audio, storagePath: sampleAudio, durationSeconds: 600, imageUrl: "retreat-mallorca", blurb: "Five breaths a minute to balance the autonomic system."),
        .init(id: 6, category: .breathwork, title: "Breath of Fire", lead: "Alma Guerra", mediaKind: .video, storagePath: sampleVideo, durationSeconds: 540, imageUrl: "retreat-kyoto", blurb: "An energizing kundalini practice to wake the body."),

        // Meditation
        .init(id: 7, category: .meditation, title: "Morning Stillness", lead: "Michelle Campos", mediaKind: .audio, storagePath: sampleAudio, durationSeconds: 600, imageUrl: "retreat-kyoto", blurb: "Begin the day with ten minutes of open awareness."),
        .init(id: 8, category: .meditation, title: "Sleep Descent", lead: "Analu Chavez", mediaKind: .audio, storagePath: sampleAudio, durationSeconds: 1200, imageUrl: "retreat-dolomites", blurb: "A long, drifting body relaxation for falling asleep."),
        .init(id: 9, category: .meditation, title: "Loving-Kindness", lead: "Mara Solé", mediaKind: .audio, storagePath: sampleAudio, durationSeconds: 840, imageUrl: "retreat-sedona", blurb: "Cultivate warmth toward yourself and others."),
    ]

    static func mock(for category: PracticeCategory) -> [PracticeSession] {
        mock.filter { $0.category == category }
    }
}

// MARK: - Practice menu (the cards on the Practice tab)

/// Every card on `PracticeView`. The first three are audio/video tracks backed
/// by `PracticeCategory`; the rest are bespoke content sections.
enum PracticeMenuItem: String, Identifiable, Hashable, CaseIterable {
    case somatic, breathwork, meditation
    case journal, exercises, recipes, massages

    var id: String { rawValue }

    /// The media category for the audio/video tracks; `nil` for bespoke sections.
    var mediaCategory: PracticeCategory? {
        switch self {
        case .somatic:    return .somatic
        case .breathwork: return .breathwork
        case .meditation: return .meditation
        default:          return nil
        }
    }

    var title: String {
        switch self {
        case .somatic, .breathwork, .meditation: return mediaCategory!.title
        case .journal:   return "Journal Prompts"
        case .exercises: return "Exercises"
        case .recipes:   return "Food Recipes"
        case .massages:  return "Personal Massages"
        }
    }

    var blurb: String {
        switch self {
        case .somatic, .breathwork, .meditation: return mediaCategory!.blurb
        case .journal:   return "Sit with a question. Short prompts to move what words can reach."
        case .exercises: return "Move with intention. Guided sequences for strength and mobility."
        case .recipes:   return "Eat to feel whole. Nourishing recipes for body and mind."
        case .massages:  return "Touch as medicine. Self-massage guides to release and restore."
        }
    }

    var systemImage: String {
        switch self {
        case .somatic, .breathwork, .meditation: return mediaCategory!.systemImage
        case .journal:   return "pencil.and.scribble"
        case .exercises: return "figure.strengthtraining.functional"
        case .recipes:   return "fork.knife"
        case .massages:  return "hands.and.sparkles"
        }
    }

    var imageName: String {
        switch self {
        case .somatic, .breathwork, .meditation: return mediaCategory!.imageName
        case .journal:   return "practice-journals"
        case .exercises: return "practice-exercises"
        case .recipes:   return "practice-recipes"
        case .massages:  return "practice-massage"
        }
    }
}

// MARK: - Journal prompts (text)

struct JournalPrompt: Identifiable, Hashable {
    let id: Int
    /// The question itself — shown as the row title and the detail heading.
    let title: String
    /// Longer framing shown on the detail screen.
    let prompt: String
    /// Theme label (e.g. "Self-compassion"), used as the eyebrow.
    let theme: String
    let imageUrl: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: JournalPrompt, rhs: JournalPrompt) -> Bool { lhs.id == rhs.id }
}

extension JournalPrompt {
    static let all: [JournalPrompt] = [
        .init(id: 1, title: "What is your body asking for today?", prompt: "Close your eyes for a breath and scan from head to toe. Without fixing anything, name what you notice — tension, hunger, restlessness, ease. Let the answer come from sensation rather than thought.", theme: "Embodiment", imageUrl: "retreat-dolomites"),
        .init(id: 2, title: "Name one thing you've outgrown.", prompt: "Think of a belief, a role, or a pattern that no longer fits who you're becoming. What would it feel like to set it down? Write to it as if saying goodbye.", theme: "Letting go", imageUrl: "retreat-sedona"),
        .init(id: 3, title: "Where did you feel ease this week?", prompt: "Recall a moment — however small — when your shoulders dropped and time softened. Describe it in detail. What made it possible, and how might you invite more of it?", theme: "Gratitude", imageUrl: "retreat-bali"),
        .init(id: 4, title: "What would self-compassion say right now?", prompt: "Picture the voice of someone who loves you unconditionally. Speak to yourself in their words about whatever you're carrying today. Notice how the body responds to kindness.", theme: "Self-compassion", imageUrl: "retreat-kyoto"),
        .init(id: 5, title: "What are you ready to begin?", prompt: "Not the whole journey — just the first honest step. Name it, and name the smallest action you could take in the next 24 hours.", theme: "Intention", imageUrl: "retreat-mallorca"),
    ]
}

// MARK: - Exercises (guided movement)

struct ExerciseStep: Identifiable, Hashable {
    let id: Int
    let name: String
    /// Sets/reps or guidance, e.g. "3 sets · 12 reps" or "Hold 30 sec".
    let detail: String
}

struct Exercise: Identifiable, Hashable {
    let id: Int
    let title: String
    /// Primary focus, e.g. "Mobility", "Core".
    let focus: String
    let durationSeconds: Int
    let imageUrl: String
    let blurb: String
    let steps: [ExerciseStep]

    var durationLabel: String {
        let minutes = max(0, durationSeconds) / 60
        return minutes == 0 ? "\(durationSeconds) sec" : "\(minutes) min"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Exercise, rhs: Exercise) -> Bool { lhs.id == rhs.id }
}

extension Exercise {
    static let all: [Exercise] = [
        .init(id: 1, title: "Morning Mobility Flow", focus: "Mobility", durationSeconds: 600, imageUrl: "retreat-mallorca", blurb: "A gentle full-body sequence to wake the joints and spine.", steps: [
            .init(id: 1, name: "Cat–Cow", detail: "8 slow reps"),
            .init(id: 2, name: "World's Greatest Stretch", detail: "5 reps each side"),
            .init(id: 3, name: "Hip Circles", detail: "10 each direction"),
            .init(id: 4, name: "Thoracic Rotations", detail: "8 each side"),
        ]),
        .init(id: 2, title: "Core Foundations", focus: "Core", durationSeconds: 720, imageUrl: "retreat-sedona", blurb: "Build deep stability with slow, controlled holds.", steps: [
            .init(id: 1, name: "Dead Bug", detail: "3 sets · 10 reps"),
            .init(id: 2, name: "Forearm Plank", detail: "3 sets · 30 sec"),
            .init(id: 3, name: "Bird Dog", detail: "3 sets · 8 each side"),
            .init(id: 4, name: "Glute Bridge", detail: "3 sets · 12 reps"),
        ]),
        .init(id: 3, title: "Posture Reset", focus: "Alignment", durationSeconds: 480, imageUrl: "retreat-dolomites", blurb: "Undo the desk slump and reopen the chest.", steps: [
            .init(id: 1, name: "Wall Angels", detail: "2 sets · 10 reps"),
            .init(id: 2, name: "Chin Tucks", detail: "2 sets · 12 reps"),
            .init(id: 3, name: "Doorway Chest Stretch", detail: "Hold 30 sec · 3x"),
        ]),
    ]
}

// MARK: - Food recipes

struct Recipe: Identifiable, Hashable {
    let id: Int
    let title: String
    /// Dietary angle or chef, e.g. "Anti-inflammatory".
    let lead: String
    let minutes: Int
    let servings: Int
    let imageUrl: String
    let blurb: String
    let ingredients: [String]
    let steps: [String]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Recipe, rhs: Recipe) -> Bool { lhs.id == rhs.id }
}

extension Recipe {
    static let all: [Recipe] = [
        .init(id: 1, title: "Golden Turmeric Lentils", lead: "Anti-inflammatory", minutes: 35, servings: 4, imageUrl: "retreat-bali", blurb: "A warming, grounding bowl built on turmeric, ginger, and red lentils.",
              ingredients: ["1 cup red lentils", "1 onion, diced", "3 cloves garlic", "1 tbsp grated ginger", "2 tsp turmeric", "1 can coconut milk", "2 cups vegetable broth", "Salt & black pepper", "Fresh cilantro to finish"],
              steps: ["Sauté onion, garlic, and ginger until soft.", "Stir in turmeric and toast for 30 seconds.", "Add lentils, coconut milk, and broth; bring to a simmer.", "Cook 20–25 minutes until lentils are tender.", "Season, then finish with fresh cilantro."]),
        .init(id: 2, title: "Overnight Oats & Berries", lead: "Gut-friendly", minutes: 10, servings: 2, imageUrl: "retreat-kyoto", blurb: "Prep tonight, wake to a fiber-rich breakfast that loves your microbiome.",
              ingredients: ["1 cup rolled oats", "1 cup milk of choice", "1/2 cup yogurt", "1 tbsp chia seeds", "1 tbsp maple syrup", "1 cup mixed berries"],
              steps: ["Combine oats, milk, yogurt, chia, and maple in a jar.", "Stir well and seal.", "Refrigerate overnight (at least 6 hours).", "Top with berries before serving."]),
        .init(id: 3, title: "Miso Glazed Salmon", lead: "Omega-3 rich", minutes: 25, servings: 2, imageUrl: "retreat-mallorca", blurb: "A ten-minute glaze turns salmon into something restorative and bright.",
              ingredients: ["2 salmon fillets", "2 tbsp white miso", "1 tbsp honey", "1 tbsp rice vinegar", "1 tsp sesame oil", "Sliced scallions", "Steamed greens to serve"],
              steps: ["Whisk miso, honey, vinegar, and sesame oil.", "Coat salmon and rest 10 minutes.", "Roast at 200°C / 400°F for 12 minutes.", "Top with scallions; serve over steamed greens."]),
    ]
}

// MARK: - Personal massages (guided self-massage)

struct Massage: Identifiable, Hashable {
    let id: Int
    let title: String
    let lead: String
    let mediaKind: MediaKind
    let storagePath: String
    let durationSeconds: Int
    let imageUrl: String
    let blurb: String
    let steps: [String]

    var durationLabel: String {
        let minutes = max(0, durationSeconds) / 60
        return minutes == 0 ? "\(durationSeconds) sec" : "\(minutes) min"
    }

    var media: MediaItem {
        MediaItem(id: id, title: title, lead: lead, imageUrl: imageUrl,
                  mediaKind: mediaKind, storagePath: storagePath, durationSeconds: durationSeconds)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Massage, rhs: Massage) -> Bool { lhs.id == rhs.id }
}

extension Massage {
    static let all: [Massage] = [
        .init(id: 1, title: "Neck & Shoulder Release", lead: "Lena Brooks", mediaKind: .video, storagePath: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4", durationSeconds: 600, imageUrl: "retreat-kyoto", blurb: "Melt the tension that gathers between the shoulder blades and the base of the skull.", steps: ["Warm the area with flat palms for 30 seconds.", "Knead the upper traps with thumb and fingers.", "Make small circles at the base of the skull.", "Finish with long downward strokes along the neck."]),
        .init(id: 2, title: "Foot Reflexology Basics", lead: "Theo Park", mediaKind: .video, storagePath: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4", durationSeconds: 480, imageUrl: "retreat-bali", blurb: "Ground the whole nervous system through the soles of the feet.", steps: ["Press and roll the arch with both thumbs.", "Walk the thumbs across the ball of the foot.", "Rotate each toe gently.", "Sweep firmly from heel to toe to close."]),
        .init(id: 3, title: "Jaw & Face Unwind", lead: "Mara Solé", mediaKind: .audio, storagePath: "https://download.samplelib.com/mp3/sample-15s.mp3", durationSeconds: 360, imageUrl: "retreat-sedona", blurb: "Release the clench we hold without noticing.", steps: ["Place fingertips on the jaw hinge.", "Make slow circles as the mouth softens open.", "Sweep along the cheekbones to the temples.", "Rest palms over the eyes and breathe."]),
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
