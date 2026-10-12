//
//  Practice.swift
//  Soulfull Gatherings
//
//  The practice library and the ledger of what a member has played: the
//  media sessions, the play and progress records, and the Practice tab's
//  cards.
//

import Foundation

// MARK: - Practices (on-demand audio / video library)

/// The three tracks surfaced on the Practice tab. `rawValue` matches the
/// `category` column in the `practice_sessions` Supabase table.
enum PracticeCategory: String, Identifiable, Hashable, CaseIterable {
    case somatic, breathwork, meditation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .somatic:    return "Somatic Exercises"
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
        case .somatic:    return "figure.cooldown"
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

    /// "Before you begin": shown above the track's sessions. Breathwork can
    /// make someone light-headed, and somatic work can bring up more than
    /// expected, so both say so — and that none of it is medical advice —
    /// before a session is chosen. Meditation needs none.
    var safetyNote: String? {
        switch self {
        case .breathwork:
            return "Breathe seated or lying down, never while driving or in water. If you feel light-headed or unwell, stop and breathe normally. This isn't medical advice: if you're pregnant or have a heart, lung or seizure condition, check with your doctor first."
        case .somatic:
            return "Move gently and stay within what feels comfortable. Pause whenever you need to, and stop if anything hurts or feels like too much. This isn't medical or psychological advice: if you have an injury or a health condition, check with your doctor first."
        case .meditation:
            return nil
        }
    }

    /// The same care in one line, under the title while a session plays.
    var safetyReminder: String? {
        switch self {
        case .breathwork: return "Stop if you feel light-headed, and breathe normally."
        case .somatic:    return "Go gently, and stop if anything hurts."
        case .meditation: return nil
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
/// `PracticePlayerView` can serve any library that grows media.
struct MediaItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let lead: String
    let imageUrl: String
    let mediaKind: MediaKind
    /// Storage object path, or an absolute `http(s)` URL for sample / public media.
    let storagePath: String
    let durationSeconds: Int
    /// Which library this came from. The player records playback against it, so
    /// two libraries' items with the same numeric id stay distinct in the
    /// ledger that creator payouts are drawn from.
    var contentKind: PracticeContentKind = .session
    /// Media track, for sessions; `nil` for other libraries.
    var category: PracticeCategory? = nil
    /// The guide it is credited to, when linked (0019) — what lets the player
    /// open their profile.
    var instructorID: String? = nil

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
    /// The guide's `instructors` row, when the session is linked to one (0019)
    /// — what makes "with …" lead somewhere. `lead` is kept equal to that
    /// guide's name server-side, so the two can't disagree.
    var instructorID: String? = nil

    var durationLabel: String {
        let minutes = max(0, durationSeconds) / 60
        return minutes == 0 ? "\(durationSeconds) sec" : "\(minutes) min"
    }

    var media: MediaItem {
        MediaItem(id: id, title: title, lead: lead, imageUrl: imageUrl,
                  mediaKind: mediaKind, storagePath: storagePath, durationSeconds: durationSeconds,
                  contentKind: .session, category: category, instructorID: instructorID)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: PracticeSession, rhs: PracticeSession) -> Bool { lhs.id == rhs.id }
}

// MARK: - Practice progress (what a member has played)

/// Which library a tracked practice came from. Mirrors the `content_kind`
/// column on `practice_plays`; the raw values are the contract with the DB
/// check constraint, so don't rename them casually — and if you drop one, drop
/// it from the constraint too or the schema keeps accepting a value no client
/// can produce (`massage` went both ways in 0012).
enum PracticeContentKind: String, Hashable, Codable, Sendable {
    case session, journal, exercise, recipe

    /// Whether this library credits a named creator. Sessions name a real guide
    /// who gets paid; the written libraries are house content for now, so they
    /// record a null creator and simply don't appear in a payout run until that
    /// changes.
    var creditsCreator: Bool {
        switch self {
        case .session:                      return true
        case .journal, .exercise, .recipe:  return false
        }
    }

    /// Whether a finished sitting counts as a **class** on the You tab, and
    /// whether its time counts toward minutes practiced. Guided practice does —
    /// the three media tracks and the Movement library, where yoga lives.
    /// Writing against a prompt and reading a recipe are practice, and they keep
    /// a streak alive, but they are not a class. Exhaustive on purpose, like
    /// `creditsCreator`: a new library won't compile until someone decides.
    var countsAsClass: Bool {
        switch self {
        case .session, .exercise:  return true
        case .journal, .recipe:    return false
        }
    }
}

/// One row of the member's own `practice_plays` ledger, reduced to what the
/// You tab's numbers are computed from. Keyed by `eventID` — the row's
/// `client_event_id`, the same key the ledger upserts on — so a sitting that
/// is still heartbeating replaces its own entry rather than adding another.
struct PracticePlayRecord: Hashable, Sendable {
    let eventID: UUID
    let kind: PracticeContentKind
    let secondsPlayed: Int
    let completed: Bool
    /// Server-stamped.
    let startedAt: Date
    /// Server-stamped, the moment `completed` latched (0029). Which local
    /// calendar day it falls on is what a streak counts: a practice day is a
    /// day something was *finished*, and a sleep meditation begun at 23:50
    /// and finished at 00:20 was finished today. Nil while unfinished.
    var completedAt: Date? = nil
}

/// One playback / reading session, addressed by a client-generated `eventID` so
/// heartbeats and retries land on the same ledger row instead of paying a
/// creator twice for one listen.
struct PracticePlay: Hashable, Sendable {
    let eventID: UUID
    let kind: PracticeContentKind
    let contentID: Int
    let title: String
    /// Snapshot of the creator's name at play time — deliberately copied rather
    /// than joined, so retitling or reassigning content can't move historical
    /// payouts. `nil` for the written libraries.
    let creator: String?
    let category: PracticeCategory?
    let durationSeconds: Int?

    init(kind: PracticeContentKind, contentID: Int, title: String,
         creator: String? = nil, category: PracticeCategory? = nil,
         durationSeconds: Int? = nil, eventID: UUID = UUID()) {
        self.eventID = eventID
        self.kind = kind
        self.contentID = contentID
        self.title = title
        self.creator = creator
        self.category = category
        self.durationSeconds = durationSeconds
    }

    /// Stable identity of the *content* (not the play), matching
    /// `PracticeProgress.id`.
    var contentKey: String { "\(kind.rawValue)-\(contentID)" }
}

extension PracticePlay {
    static func media(_ item: MediaItem) -> PracticePlay {
        PracticePlay(kind: item.contentKind, contentID: item.id, title: item.title,
                     creator: item.lead, category: item.category,
                     durationSeconds: item.durationSeconds)
    }

    /// A prompt has no intrinsic length, but it needs a nominal one: it is the
    /// bound the DB trigger clamps `seconds_played` against
    /// (`least(seconds_played, duration_seconds)`), and with it null the clamp
    /// is skipped entirely and a journal play accrues without limit. Fifteen
    /// minutes is a long sitting with one prompt.
    static func journal(_ prompt: JournalPrompt) -> PracticePlay {
        PracticePlay(kind: .journal, contentID: prompt.id, title: prompt.title,
                     durationSeconds: 900)
    }

    static func exercise(_ exercise: Exercise) -> PracticePlay {
        PracticePlay(kind: .exercise, contentID: exercise.id, title: exercise.title,
                     durationSeconds: exercise.durationSeconds)
    }

    /// `Recipe.angle` is a dietary angle ("Anti-inflammatory"), not a person,
    /// so it is deliberately NOT passed as the creator — a payout run must
    /// never try to pay "Gut-friendly".
    static func recipe(_ recipe: Recipe) -> PracticePlay {
        PracticePlay(kind: .recipe, contentID: recipe.id, title: recipe.title,
                     durationSeconds: recipe.minutes * 60)
    }
}

/// A member's standing with one practice, read back from the `practice_progress`
/// view (which aggregates every play of it).
struct PracticeProgress: Identifiable, Hashable, Sendable {
    let kind: PracticeContentKind
    let contentID: Int
    let title: String
    let creator: String?
    let category: PracticeCategory?
    /// Where to pick the media back up.
    let positionSeconds: Int
    let durationSeconds: Int?
    /// Summed across every replay — this is the payout-relevant number.
    let totalSecondsPlayed: Int
    let completed: Bool
    let playCount: Int
    /// When it was last opened — finished or not.
    let lastPlayedAt: Date
    /// When it was last FINISHED (`practice_progress.last_completed_at`, 0029).
    /// Not `lastPlayedAt`: a practice finished last month and opened for two
    /// seconds today was played today, but finished last month — and a
    /// digital-retreat day asks when it was finished.
    var lastCompletedAt: Date? = nil

    var id: String { "\(kind.rawValue)-\(contentID)" }

    /// How far through, 0–1. Zero when the length isn't known.
    var fraction: Double {
        guard let durationSeconds, durationSeconds > 0 else { return completed ? 1 : 0 }
        return min(1, max(0, Double(positionSeconds) / Double(durationSeconds)))
    }

    /// Started, but not finished — the set the "Continue" card draws from.
    /// A few seconds in doesn't count as started; that's usually a mis-tap.
    var isResumable: Bool {
        !completed && positionSeconds >= 10 && fraction < 0.95
    }

    var remainingLabel: String? {
        guard let durationSeconds, durationSeconds > positionSeconds else { return nil }
        let minutes = max(1, (durationSeconds - positionSeconds) / 60)
        return "\(minutes) min left"
    }

    /// Where this practice lives on the Practice tab, so a "Continue" tap can
    /// route to it. Total by design: every kind the ledger can hold has a
    /// section that opens it, and the exhaustive switch is what keeps that true
    /// — retiring a library again won't compile until someone decides where its
    /// history should land.
    var menuItem: PracticeMenuItem {
        switch kind {
        case .session:  return category.map(PracticeMenuItem.init(category:)) ?? .somatic
        case .journal:  return .journal
        case .exercise: return .movement
        case .recipe:   return .recipes
        }
    }
}

// MARK: - Practice menu (the cards on the Practice tab)

/// Every card on `PracticeView`. The first three are audio/video tracks backed
/// by `PracticeCategory`; the rest are bespoke content sections.
///
/// `movement` is the section the `Exercise` library lives in — the card reads
/// "Movement" while the items on it are still exercises. The content type keeps
/// its own name because `PracticeContentKind.exercise` is a DB contract.
enum PracticeMenuItem: String, Identifiable, Hashable, CaseIterable {
    case somatic, breathwork, meditation
    case journal, movement, recipes

    var id: String { rawValue }

    /// The card that hosts a given media track.
    init(category: PracticeCategory) {
        switch category {
        case .somatic:    self = .somatic
        case .breathwork: self = .breathwork
        case .meditation: self = .meditation
        }
    }

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
        case .journal:  return "Journal Prompts"
        case .movement: return "Movement"
        case .recipes:  return "Food Recipes"
        }
    }

    var blurb: String {
        switch self {
        case .somatic, .breathwork, .meditation: return mediaCategory!.blurb
        case .journal:  return "Sit with a question. Short prompts to move what words can reach."
        case .movement: return "Move with intention. Guided sequences for strength and mobility."
        case .recipes:  return "Eat to feel whole. Nourishing recipes for body and mind."
        }
    }

    var systemImage: String {
        switch self {
        case .somatic, .breathwork, .meditation: return mediaCategory!.systemImage
        case .journal:  return "pencil.and.scribble"
        case .movement: return "figure.strengthtraining.functional"
        case .recipes:  return "fork.knife"
        }
    }

    var imageName: String {
        switch self {
        case .somatic, .breathwork, .meditation: return mediaCategory!.imageName
        case .journal:  return "practice-journals"
        case .movement: return "practice-exercises"
        case .recipes:  return "practice-recipes"
        }
    }
}
