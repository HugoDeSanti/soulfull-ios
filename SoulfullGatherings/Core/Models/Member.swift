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
    var fullName: String
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

/// How long a name may be: 64 characters, the limit `profiles.full_name` and
/// `instructors.name` hold (0030). Names reach every member through the feed,
/// and a guide's through every page they made, so they need a ceiling.
///
/// Counted the way Postgres's `char_length` counts, in Unicode code points,
/// but cut only between characters: an accent or an emoji is never split, and
/// a name that fits here is never refused there.
enum MemberName {
    static let maxLength = 64

    /// For a text field: cut to the limit as it is typed, spaces kept (one
    /// between two words is part of the name).
    static func capped(_ text: String) -> String {
        var scalars = 0
        for index in text.indices {
            scalars += text[index].unicodeScalars.count
            if scalars > maxLength { return String(text[..<index]) }
        }
        return text
    }

    /// What is stored: trimmed, then cut to the limit.
    static func limited(_ name: String) -> String {
        capped(name.trimmingCharacters(in: .whitespacesAndNewlines))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How other members see the name in Community, the way the server's
    /// `community_display_name()` shortens it: the first word and the SECOND
    /// word's initial ("Hugo De Santiago" → "Hugo D."), a single word as it is.
    /// Nil for no name. (The server also hides an objectionable name, which
    /// this doesn't try to know.)
    static func shownInCommunity(_ name: String) -> String? {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return nil }
        guard words.count > 1, let initial = words[1].first else { return first }
        return "\(first) \(initial)."
    }
}
