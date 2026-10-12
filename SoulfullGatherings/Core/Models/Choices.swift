//
//  Choices.swift
//  Soulfull Gatherings
//
//  The fixed choices the app offers: onboarding's answers and Home's mood
//  chips.
//

import Foundation

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
    /// Where this feeling points in the library. Selecting a chip rewrites
    /// Home's ritual card and sends "Begin now" here — the chips used to set
    /// state nothing read, which made the first interactive control on the
    /// main screen a no-op.
    let suggests: PracticeMenuItem
    /// Ritual-card headline for this mood.
    let ritual: String
    /// One line under the headline.
    let ritualLead: String
}

extension MoodChip {
    /// Shown when no mood is selected.
    static let defaultRitual = (
        title: "Begin where you are",
        lead: "A short practice for whatever today is",
        destination: PracticeMenuItem.journal
    )

    // Every mood points at a section that actually has content in v1
    // (journal / movement / recipes). The three media tracks are deliberately
    // absent — they read "Coming soon" until `practice_sessions` is seeded, and
    // a suggestion that lands on a locked card is a dead end. Each `ritual` /
    // `ritualLead` pair names something really in that section, so retiring a
    // library means rewriting the chips that point into it, not just repointing
    // them — Anxious and Tender both needed new copy when Personal Massages went.
    static let all: [MoodChip] = [
        .init(id: "anxious",  label: "Anxious",  suggests: .movement,
              ritual: "Move it through",       ritualLead: "Gentle movement to settle a racing body"),
        .init(id: "grateful", label: "Grateful", suggests: .journal,
              ritual: "Name it while it's here", ritualLead: "A prompt for what's already good"),
        .init(id: "tired",    label: "Tired",    suggests: .recipes,
              ritual: "Eat something warm",    ritualLead: "Nourishment that asks nothing of you"),
        .init(id: "joyful",   label: "Joyful",   suggests: .movement,
              ritual: "Move with it",          ritualLead: "Let the body spend some of that"),
        .init(id: "tender",   label: "Tender",   suggests: .journal,
              ritual: "Speak to yourself kindly", ritualLead: "A prompt for a soft day"),
        .init(id: "calm",     label: "Calm",     suggests: .journal,
              ritual: "Stay a while",          ritualLead: "A prompt to sit with the quiet"),
        .init(id: "lost",     label: "Lost",     suggests: .journal,
              ritual: "Find one true thing",   ritualLead: "Short questions for when the map is gone"),
        .init(id: "hopeful",  label: "Hopeful",  suggests: .movement,
              ritual: "Build on it",           ritualLead: "A sequence for strength and momentum"),
        .init(id: "sad",      label: "Sad",      suggests: .journal,
              ritual: "Let it have room",      ritualLead: "A prompt that doesn't rush you"),
        .init(id: "peaceful", label: "Peaceful", suggests: .recipes,
              ritual: "Make something slow",   ritualLead: "Cooking as the practice"),
        .init(id: "angry",    label: "Angry",    suggests: .movement,
              ritual: "Put it somewhere",      ritualLead: "Move the heat out through the body"),
        .init(id: "inspired", label: "Inspired", suggests: .journal,
              ritual: "Catch it in writing",   ritualLead: "Before the thought moves on"),
    ]
}
