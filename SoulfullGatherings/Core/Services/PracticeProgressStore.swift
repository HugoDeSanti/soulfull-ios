//
//  PracticeProgressStore.swift
//  Soulfull Gatherings
//
//  The app's view of what this member has practised — read from the
//  `practice_progress` view, written as rows on `practice_plays`.
//
//  Progress is held on the SERVER, not the device, for two reasons. The first is
//  the member's: a practice half-finished on the phone should still be
//  half-finished after a reinstall. The second is the business's: these rows are
//  the record content-creator payouts are calculated from, so they have to
//  survive the device they were made on. See 0008_practice_progress.sql.
//

import SwiftUI

@Observable @MainActor
final class PracticeProgressStore {

    static let shared = PracticeProgressStore()

    /// Keyed by `PracticeProgress.id` ("session-4", "journal-2", …).
    private(set) var progress: [String: PracticeProgress] = [:]
    private(set) var isLoading = false
    /// Whose progress is in `progress`, so a session change forces a reload
    /// rather than showing the previous member's history.
    private(set) var loadedFor: UUID?

    /// Read straight from the live session rather than threaded through the
    /// view tree: the player is a sheet and the detail screens are deep in a
    /// stack, and every one of them would otherwise need an `AuthManager`.
    private var userID: UUID? { SupabaseService.shared.client.auth.currentUser?.id }

    // MARK: - Loading

    /// Loads (or reloads) this member's history. Cheap to call on appear —
    /// it no-ops when the same member's data is already in hand.
    func refresh(force: Bool = false) async {
        guard let userID else { clear(); return }
        guard force || loadedFor != userID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await SupabaseService.shared.fetchPracticeProgress(userID: userID)
            progress = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            loadedFor = userID
        } catch where error.isCancellation {
        } catch {
            // A missing table (before 0008 is applied) or a dropped connection
            // both mean "no history to show" — the Practice tab and Home simply
            // render as they did before progress existed.
            Log.data.info("Practice progress unavailable: \(error.localizedDescription)")
            if loadedFor != userID { progress = [:] }
        }
    }

    /// The member the current session belongs to. Capture this when a practice
    /// opens and hand it back to `record` — see that method.
    var currentUserID: UUID? { userID }

    /// Drops everything in memory. Called on sign-out so the next member
    /// doesn't briefly see the previous one's continue card.
    func clear() {
        progress = [:]
        loadedFor = nil
        foldedSeconds.removeAll()
    }

    // MARK: - Reading

    func progress(kind: PracticeContentKind, contentID: Int) -> PracticeProgress? {
        progress["\(kind.rawValue)-\(contentID)"]
    }

    func progress(for play: PracticePlay) -> PracticeProgress? {
        progress[play.contentKey]
    }

    /// The most recently started practice that isn't finished — what "Continue
    /// where you left off" offers. Nothing is invented: with no history, there
    /// is no card.
    var resumable: PracticeProgress? {
        progress.values
            .filter(\.isResumable)
            .max { $0.lastPlayedAt < $1.lastPlayedAt }
    }

    /// Distinct days practised in a row, counting back from today. Yesterday
    /// still counts as a live streak — today isn't over yet.
    var streakDays: Int {
        let calendar = Calendar.current
        let days = Set(progress.values.map { calendar.startOfDay(for: $0.lastPlayedAt) })
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: .now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        var cursor = days.contains(today) ? today : yesterday
        guard days.contains(cursor) else { return 0 }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Practices touched in the last seven days.
    var practicesThisWeek: Int {
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 3600)
        return progress.values.filter { $0.lastPlayedAt >= cutoff }.count
    }

    // MARK: - Writing

    /// Records consumption against the ledger and folds the result into the
    /// local map so the UI updates without a round trip.
    ///
    /// Never throws: a lost heartbeat costs a few seconds of attribution, and
    /// nothing about playback should stall or fail because a write did.
    /// - Parameter owner: the member this play belongs to, captured when the
    ///   practice was opened. Reading `userID` here instead meant a sign-out
    ///   mid-playback attributed the final heartbeat to whoever the session
    ///   belonged to *now* — in practice the fresh anonymous guest.
    func record(_ play: PracticePlay,
                owner: UUID?,
                secondsPlayed: Int,
                positionSeconds: Int,
                completed: Bool) async {
        guard let userID, let owner, owner == userID else { return }
        applyLocally(play, secondsPlayed: secondsPlayed, positionSeconds: positionSeconds, completed: completed)
        do {
            try await SupabaseService.shared.recordPracticePlay(
                play,
                userID: userID,
                secondsPlayed: secondsPlayed,
                positionSeconds: positionSeconds,
                completed: completed
            )
        } catch {
            Log.data.error("Couldn't record practice play: \(error.localizedDescription)")
        }
    }

    /// Optimistic local mirror of what the server will compute. Deliberately
    /// approximate — the next `refresh()` replaces it with the real aggregate.
    /// Only `positionSeconds` / `completed` / `lastPlayedAt` drive any UI;
    /// `totalSecondsPlayed` is carried for consistency, and the authoritative
    /// figure for a payout is always the server's.
    private func applyLocally(_ play: PracticePlay,
                              secondsPlayed: Int,
                              positionSeconds: Int,
                              completed: Bool) {
        let key = play.contentKey
        let existing = progress[key]

        // The play row is UPSERTED, so this heartbeat's seconds replace what the
        // same play reported a moment ago rather than adding to it. Back out
        // what we last folded in for this event before folding in the new total.
        let alreadyFolded = foldedSeconds[play.eventID] ?? 0
        let carried = max(0, (existing?.totalSecondsPlayed ?? 0) - alreadyFolded)
        foldedSeconds[play.eventID] = secondsPlayed

        progress[key] = PracticeProgress(
            kind: play.kind,
            contentID: play.contentID,
            title: play.title,
            creator: play.creator,
            category: play.category,
            positionSeconds: positionSeconds,
            durationSeconds: play.durationSeconds ?? existing?.durationSeconds,
            totalSecondsPlayed: carried + secondsPlayed,
            completed: completed || (existing?.completed ?? false),
            playCount: max(existing?.playCount ?? 1, 1),
            lastPlayedAt: .now
        )
    }

    /// Seconds already folded into the optimistic mirror for an in-flight play.
    /// Bounded by the number of practices opened in one app session.
    private var foldedSeconds: [UUID: Int] = [:]
}
