//
//  WrittenPractice.swift
//  Soulfull Gatherings
//
//  The written libraries: journal prompts, movement sequences and
//  recipes.
//

import Foundation

// MARK: - Written practices (journal prompts, movement, recipes)
//
// Each library is a table (0021) — `journal_prompts`, `exercises`, `recipes` —
// read through `WrittenPracticeStore`. They lived here as `.all` arrays until
// 2026-09-29, which made every new prompt and every typo fix a release.
//
// The ids are a contract with the practice ledger, program curricula and a
// member's saved reflections, none of which can follow a renumbering. Each one
// names its guide on its own row (`instructorID`, 0022), as sessions and
// digital retreats do. `.mock` on each type is a preview / DEBUG fixture only — never a
// fallback for a library that failed to load.

struct JournalPrompt: Identifiable, Hashable, Codable {
    let id: Int
    /// The question itself — shown as the row title and the detail heading.
    let title: String
    /// Longer framing shown on the detail screen.
    let prompt: String
    /// Theme label (e.g. "Self-compassion"), used as the eyebrow.
    let theme: String
    let imageUrl: String
    /// The guide on its page and in whose library it appears. Display only —
    /// the written libraries take no part in payouts (`creditsCreator`).
    var instructorID: String? = nil

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: JournalPrompt, rhs: JournalPrompt) -> Bool { lhs.id == rhs.id }
}

struct ExerciseStep: Identifiable, Hashable, Codable {
    /// Its place in the sequence, from 1. Steps are stored as an ordered list,
    /// so the position is their only identity.
    let id: Int
    let name: String
    /// Sets/reps or guidance, e.g. "3 sets · 12 reps" or "Hold 30 sec". Nil
    /// when the name says it all.
    let detail: String?
}

struct Exercise: Identifiable, Hashable, Codable {
    let id: Int
    let title: String
    /// Primary focus, e.g. "Mobility", "Core".
    let focus: String
    let durationSeconds: Int
    let imageUrl: String
    let blurb: String
    let steps: [ExerciseStep]
    /// See `JournalPrompt.instructorID`.
    var instructorID: String? = nil

    var durationLabel: String {
        let minutes = max(0, durationSeconds) / 60
        return minutes == 0 ? "\(durationSeconds) sec" : "\(minutes) min"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Exercise, rhs: Exercise) -> Bool { lhs.id == rhs.id }
}

struct Recipe: Identifiable, Hashable, Codable {
    let id: Int
    let title: String
    /// A dietary angle, e.g. "Anti-inflammatory" — never a person. A recipe's
    /// guide, if it has one, is `instructorID`.
    let angle: String
    let minutes: Int
    let servings: Int
    let imageUrl: String
    let blurb: String
    let ingredients: [String]
    let steps: [String]
    /// See `JournalPrompt.instructorID`.
    var instructorID: String? = nil

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Recipe, rhs: Recipe) -> Bool { lhs.id == rhs.id }
}

/// The three written libraries as the app holds them: published rows only, in
/// the team's order.
struct WrittenLibrary: Hashable, Sendable, Codable {
    var journals: [JournalPrompt] = []
    var exercises: [Exercise] = []
    var recipes: [Recipe] = []

    static let empty = WrittenLibrary()

    var isEmpty: Bool { journals.isEmpty && exercises.isEmpty && recipes.isEmpty }

    func journal(id: Int) -> JournalPrompt? { journals.first { $0.id == id } }
    func exercise(id: Int) -> Exercise? { exercises.first { $0.id == id } }
    func recipe(id: Int) -> Recipe? { recipes.first { $0.id == id } }
}
