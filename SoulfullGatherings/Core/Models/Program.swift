//
//  Program.swift
//  Soulfull Gatherings
//
//  Digital retreats ("programs" in code): the catalog row, the authored
//  curriculum, and a member's standing in it.
//

import Foundation

// MARK: - Digital programs (the Programs tab)

/// A self-paced, multi-day guided journey. The catalog row; the day-by-day
/// content hangs off `curriculum`.
///
/// Sourced from the `programs` table. There is deliberately **no** offline
/// fallback for the real catalog — `mock` below exists for previews and the
/// DEBUG `-preview-*` screens only, exactly as `Retreat.mock` does.
struct Program: Identifiable, Hashable {
    let id: String
    let title: String
    /// The guide who leads it.
    let lead: String
    /// A display date range, and normally **nil**. A program is self-paced, so
    /// the meta line is derived from `days` and cannot drift from the content.
    /// Set it only to deliberately override that — the same opt-out
    /// `RetreatExperience.dateRange` offers the brochure.
    let when: String?
    let days: Int
    let imageUrl: String
    let blurb: String?
    /// The authored days. Nil when the column is empty **or when it failed to
    /// decode** — see `ProgramRow.decodedCurriculum`, which fails soft. A
    /// program with no curriculum is shown in the catalog but cannot be
    /// started, because there is nothing to start.
    let curriculum: ProgramCurriculum?
    /// False for a draft, or for a program taken down after members joined it.
    /// The catalog never sees one (`fetchPrograms` filters on it); the You tab
    /// can, because a program someone finished is still part of their history
    /// even once it's gone from the shelf — it just can't be opened any more.
    let published: Bool
    /// The guide's `instructors` row, when linked (0019). `lead` is its name.
    let instructorID: String?

    init(id: String, title: String, lead: String, when: String? = nil, days: Int,
         imageUrl: String, blurb: String? = nil, curriculum: ProgramCurriculum? = nil,
         published: Bool = true, instructorID: String? = nil) {
        self.id = id
        self.title = title
        self.lead = lead
        self.when = when
        self.days = days
        self.imageUrl = imageUrl
        self.blurb = blurb
        self.curriculum = curriculum
        self.published = published
        self.instructorID = instructorID
    }

    /// What the catalog card and the detail header say about length.
    var metaLine: String {
        when ?? "\(days) \(days == 1 ? "day" : "days") · Self-paced"
    }

    /// The days actually authored. The catalog's `days` column is a display
    /// number and the two can disagree if someone edits one and not the other;
    /// everything that walks the program uses this.
    var authoredDays: [ProgramDay] { curriculum?.days ?? [] }

    /// A program with no authored days cannot be enrolled in.
    var isStartable: Bool { !authoredDays.isEmpty }

    /// Hashed by id, but EQUAL only when everything is: `==` used to compare
    /// ids alone, so a program re-authored under a member read as unchanged
    /// and a page handed the new copy could keep drawing the old one.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The hand-authored `programs.curriculum` document.
///
/// Decoding **fails soft** at the row level (see `ProgramRow`), which means a
/// broken curriculum looks exactly like an unauthored one. When someone says a
/// program "has no days", check the log for a decode error before assuming the
/// column is empty — the same trap `retreats.experience` carries.
struct ProgramCurriculum: Hashable, Sendable, Decodable {
    /// One paragraph on the arc of the whole program.
    let overview: String?
    let days: [ProgramDay]
    /// Shown once the last day is complete.
    let closing: ProgramClosing?

    enum CodingKeys: String, CodingKey { case overview, days, closing }

    init(overview: String? = nil, days: [ProgramDay], closing: ProgramClosing? = nil) {
        self.overview = overview
        self.days = days.sorted { $0.day < $1.day }
        self.closing = closing
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.overview = try c.decodeIfPresent(String.self, forKey: .overview)
        self.closing = try c.decodeIfPresent(ProgramClosing.self, forKey: .closing)
        // Sorted rather than trusted: the unlock rule walks days in order, and
        // a curriculum authored out of sequence would otherwise gate the wrong
        // one.
        self.days = (try c.decodeIfPresent([ProgramDay].self, forKey: .days) ?? [])
            .sorted { $0.day < $1.day }
    }
}

struct ProgramClosing: Hashable, Sendable, Decodable {
    let title: String
    let body: String
}

/// One day of a program.
struct ProgramDay: Identifiable, Hashable, Sendable, Decodable {
    /// 1-based. This is the identity the completion rows are keyed on, so it
    /// must not be renumbered once a program is live.
    let day: Int
    let title: String
    let intention: String?
    let imageUrl: String?
    let activities: [ProgramActivity]

    var id: Int { day }

    enum CodingKeys: String, CodingKey {
        case day, title, intention, activities
        case imageUrl = "image_url"
    }

    init(day: Int, title: String, intention: String? = nil,
         imageUrl: String? = nil, activities: [ProgramActivity]) {
        self.day = day
        self.title = title
        self.intention = intention
        self.imageUrl = imageUrl
        self.activities = activities
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let day = try c.decode(Int.self, forKey: .day)
        self.day = day
        self.title = try c.decode(String.self, forKey: .title)
        self.intention = try c.decodeIfPresent(String.self, forKey: .intention)
        self.imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        // Lossy on purpose. One unreadable activity — a `kind` this build
        // doesn't know, a missing id — costs that activity, not the program.
        // The alternative is a single typo in hand-authored JSON emptying the
        // whole tab.
        var list = try c.nestedUnkeyedContainer(forKey: .activities)
        var parsed: [ProgramActivity] = []
        while !list.isAtEnd {
            if let activity = try? list.decode(ProgramActivity.self) {
                parsed.append(activity)
            } else {
                _ = try? list.decode(AnyDecodableSkip.self)
                // `day`, not `self.day`: a log interpolation is an autoclosure
                // and can't capture a mutating self mid-initialiser.
                Log.data.error("Program day \(day, privacy: .public): skipped an unreadable activity")
            }
        }
        self.activities = parsed
    }
}

/// Consumes one element of an unkeyed container whose contents we don't care
/// about, so a failed `decode` can be stepped over instead of wedging the loop.
private struct AnyDecodableSkip: Decodable {
    init(from decoder: any Decoder) throws {}
}

/// A pointer from a program day into one of the practice libraries.
///
/// It is a *reference*, not a copy: the content itself still lives in
/// `practice_sessions` or the hardcoded libraries, and playing it records to
/// `practice_plays` exactly as it would from the Practice tab. A creator is
/// paid the same whether their session was found in the library or in a
/// program.
struct ProgramActivity: Identifiable, Hashable, Sendable, Decodable {
    let kind: PracticeContentKind
    let contentID: Int
    /// An optional line of framing from the guide, shown under the row.
    let note: String?

    /// Matches `PracticeProgress.id`, which is how completion is looked up.
    var id: String { "\(kind.rawValue)-\(contentID)" }

    enum CodingKeys: String, CodingKey {
        case kind, note
        case contentID = "content_id"
    }

    init(kind: PracticeContentKind, contentID: Int, note: String? = nil) {
        self.kind = kind
        self.contentID = contentID
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .kind)
        // Strict, unlike `PracticePlay`'s read-side `?? .session`: mis-filing a
        // curriculum entry under the wrong library would send the member to the
        // wrong screen, and the lossy decode above turns this throw into a
        // skipped row rather than a broken program.
        guard let kind = PracticeContentKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c,
                debugDescription: "Unknown practice content kind '\(raw)'")
        }
        self.kind = kind
        self.contentID = try c.decode(Int.self, forKey: .contentID)
        self.note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

/// A member's standing with one program, from `program_enrollments`.
struct ProgramEnrollment: Hashable, Sendable {
    let programID: String
    let enrolledAt: Date
    let completedAt: Date?
}

/// One finished day, from `program_day_completions`.
///
/// `completedAt` is a **server** timestamp and the input to the next day's
/// unlock. It is compared against `practice_progress.last_played_at`, which is
/// also server-stamped, so the two are on the same clock — the device's only
/// contribution is deciding which calendar day a given instant falls in.
struct ProgramDayCompletion: Hashable, Sendable {
    let programID: String
    let day: Int
    let completedAt: Date
}

/// Whether a day can be opened, and if not, why not.
///
/// Both halves of the rule are represented, because they need different words:
/// "finish today first" and "come back tomorrow" are not the same message and
/// a single `locked` case would have to guess which one to show.
enum ProgramDayState: Hashable, Sendable {
    /// Every activity done, on the date it was finished.
    case complete(Date)
    /// Open now.
    case open
    /// The previous day is done, but the calendar hasn't turned over yet.
    case opens(Date)
    /// The previous day is still unfinished.
    case awaitingPreviousDay

    var isOpen: Bool { self == .open }
    var isComplete: Bool { if case .complete = self { return true }; return false }
}
