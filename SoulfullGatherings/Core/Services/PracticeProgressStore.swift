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

/// Whether a member's own history has been read — shared by this store's
/// ledger and by `ProgramStore`, whose `refresh` swallows its errors.
///
/// Exists so "nothing here" and "couldn't find out" never render the same:
/// telling someone on a train they have no digital retreats is the same
/// mistake the catalog made before `RetreatsLoadFailure`.
enum HistoryLoadStatus: Equatable {
    case notLoaded
    case loaded
    /// Couldn't be read, and there's nothing from earlier to show instead.
    /// `offline` picks the words — see `Error.isOffline`.
    case unavailable(offline: Bool)
}

@Observable @MainActor
final class PracticeProgressStore {

    static let shared = PracticeProgressStore()

    /// Keyed by `PracticeProgress.id` ("session-4", "journal-2", …).
    private(set) var progress: [String: PracticeProgress] = [:]
    private(set) var isLoading = false
    /// Whose progress is in `progress`, so a session change forces a reload
    /// rather than showing the previous member's history.
    private(set) var loadedFor: UUID?

    /// Every sitting this member has recorded, keyed by `client_event_id` —
    /// the raw ledger the You tab's numbers and the streak are computed from.
    /// `progress` can't serve: it keeps one date per practice, so the same
    /// meditation done daily for a week reads as a single day.
    private(set) var ledger: [UUID: PracticePlayRecord] = [:]
    private(set) var ledgerStatus: HistoryLoadStatus = .notLoaded
    private var ledgerLoadedFor: UUID?

    /// Read straight from the live session rather than threaded through the
    /// view tree: the player is a sheet and the detail screens are deep in a
    /// stack, and every one of them would otherwise need an `AuthManager`.
    private var userID: UUID? { SupabaseService.shared.client.auth.currentUser?.id }

    // MARK: - Loading

    /// Loads (or reloads) this member's history. Cheap to call on appear —
    /// it no-ops when the same member's data is already in hand.
    ///
    /// `force` re-reads the per-practice progress, which the players do after
    /// every sitting. It does NOT re-page the whole ledger: that is kept current
    /// by `record` as sittings happen, so it is only fetched once per member
    /// (and retried while it has never loaded) — see `reloadAll` for the
    /// deliberate refresh.
    func refresh(force: Bool = false) async {
        guard let userID else { clear(); return }
        async let progressLoad: Void = refreshProgress(for: userID, force: force)
        async let ledgerLoad: Void = refreshLedger(for: userID, force: false)
        _ = await (progressLoad, ledgerLoad)
    }

    /// Everything, from the server — pull to refresh on the You tab, which is
    /// where a sitting recorded on another device would otherwise stay
    /// invisible until the next launch.
    func reloadAll() async {
        guard let userID else { clear(); return }
        async let progressLoad: Void = refreshProgress(for: userID, force: true)
        async let ledgerLoad: Void = refreshLedger(for: userID, force: true)
        _ = await (progressLoad, ledgerLoad)
    }

    private func refreshProgress(for userID: UUID, force: Bool) async {
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

    private func refreshLedger(for userID: UUID, force: Bool) async {
        guard force || ledgerLoadedFor != userID || ledgerStatus != .loaded else { return }
        do {
            let rows = try await SupabaseService.shared.fetchPracticeLedger(userID: userID)
            // The session can change while the pages load; don't hand one
            // member's history to the next.
            guard self.userID == userID else { return }
            ledger = Dictionary(rows.map { ($0.eventID, $0) }, uniquingKeysWith: { $1 })
            ledgerLoadedFor = userID
            ledgerStatus = .loaded
        } catch where error.isCancellation {
        } catch {
            Log.data.info("Practice ledger unavailable: \(error.localizedDescription)")
            // Numbers already on screen for this member are better than none;
            // only a member with nothing loaded yet is told it failed.
            if ledgerLoadedFor != userID {
                ledger = [:]
                ledgerStatus = .unavailable(offline: error.isOffline)
            }
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
        ledger = [:]
        ledgerLoadedFor = nil
        ledgerStatus = .notLoaded
        foldedSeconds.removeAll()
    }

    #if DEBUG
    /// `-preview-you` only: stands a fixture ledger in for the member's own,
    /// and marks it loaded for this session so a `refresh` can't replace it.
    func installPreviewLedger(_ records: [PracticePlayRecord]) {
        ledger = Dictionary(records.map { ($0.eventID, $0) }, uniquingKeysWith: { $1 })
        ledgerLoadedFor = userID
        ledgerStatus = .loaded
    }
    #endif

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

    /// The You tab's numbers, and the streak Home names. Computed from the
    /// ledger on each read; read it once per `body`.
    var stats: PracticeStats { PracticeStats(ledger.values, now: AppClock.shared.now) }

    /// The current streak — see `PracticeStats` for what makes a day count.
    /// Home's "N days in a row" and the You tab read the same figure, so the
    /// two can never disagree.
    var streakDays: Int { stats.currentStreak }

    /// Practices touched in the last seven days.
    var practicesThisWeek: Int {
        let cutoff = AppClock.shared.now.addingTimeInterval(-7 * 24 * 3600)
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
        applyToLedger(play, secondsPlayed: secondsPlayed, completed: completed)
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

    /// Mirrors the ledger row this heartbeat upserts, applying the same rules
    /// the DB trigger does — seconds never go backwards and are clamped to the
    /// practice's length, completion latches, `started_at` is fixed by the
    /// first write — so finishing a practice moves the streak and the class
    /// count at once, not at the next launch.
    private func applyToLedger(_ play: PracticePlay, secondsPlayed: Int, completed: Bool) {
        let existing = ledger[play.eventID]
        var seconds = max(secondsPlayed, existing?.secondsPlayed ?? 0)
        if let duration = play.durationSeconds { seconds = min(seconds, duration) }
        ledger[play.eventID] = PracticePlayRecord(
            eventID: play.eventID,
            kind: play.kind,
            secondsPlayed: seconds,
            completed: completed || (existing?.completed ?? false),
            startedAt: existing?.startedAt ?? .now
        )
    }
}

// MARK: - Stats

/// A member's practice, in the four numbers the You tab shows.
///
/// **What counts, decided 2026-09-18:**
/// - A **practice day** is a local calendar day on which *any* practice was
///   finished — a journal entry or a recipe included. Opening one isn't
///   enough: the ledger records a sitting after five seconds on screen, and a
///   glance is not a day of practice.
/// - A **class** is a finished sitting of a session or a Movement sequence
///   (`PracticeContentKind.countsAsClass`). Each sitting counts, so doing the
///   same class twice is two.
/// - **Minutes** are the time actually spent in those same classes — media
///   time for audio/video, foreground time on screen for movement — whether or
///   not the sitting was finished. Not the length of what was opened.
struct PracticeStats: Equatable {
    let currentStreak: Int
    let bestStreak: Int
    /// Whether today already counts toward the streak — a practice was
    /// FINISHED today. A streak carried by yesterday alone is still alive, but
    /// today is what keeps it.
    let keptToday: Bool
    /// Whether anything was practised today at all, finished or not. Not the
    /// same as `keptToday`, and the difference is the one a member notices: a
    /// prompt opened and not written in, or a session stopped short, is real
    /// practice — telling them "practice today" after it reads as though it
    /// never happened. The ledger only holds a sitting once there was real
    /// activity (5s on screen, or media actually played), so any row counts.
    let practicedToday: Bool
    let classesTaken: Int
    let minutesPracticed: Int

    init(_ plays: some Sequence<PracticePlayRecord>,
         calendar: Calendar = .current,
         now: Date = .now) {
        let today = calendar.startOfDay(for: now)
        var days = Set<Date>()
        var touchedToday = false
        var classes = 0
        var seconds = 0
        for play in plays {
            let day = calendar.startOfDay(for: play.startedAt)
            if day == today { touchedToday = true }
            if play.completed { days.insert(day) }
            guard play.kind.countsAsClass else { continue }
            if play.completed { classes += 1 }
            seconds += max(0, play.secondsPlayed)
        }
        classesTaken = classes
        minutesPracticed = seconds / 60

        keptToday = days.contains(today)
        practicedToday = touchedToday
        currentStreak = Self.run(endingOn: today, in: days, calendar: calendar)
            // Yesterday still counts as a live streak — today isn't over yet.
            ?? Self.step(today, by: -1, calendar)
                .flatMap { Self.run(endingOn: $0, in: days, calendar: calendar) }
            ?? 0

        // Longest run: walk forward from every day that starts one.
        var best = 0
        for day in days {
            guard let previous = Self.step(day, by: -1, calendar),
                  !days.contains(previous) else { continue }
            var length = 0
            var cursor: Date? = day
            while let current = cursor, days.contains(current) {
                length += 1
                cursor = Self.step(current, by: 1, calendar)
            }
            best = max(best, length)
        }
        bestStreak = max(best, currentStreak)
    }

    /// Consecutive days ending on `day`, or nil if `day` itself wasn't one.
    private static func run(endingOn day: Date, in days: Set<Date>, calendar: Calendar) -> Int? {
        guard days.contains(day) else { return nil }
        var length = 0
        var cursor: Date? = day
        while let current = cursor, days.contains(current) {
            length += 1
            cursor = step(current, by: -1, calendar)
        }
        return length
    }

    /// The start of the day `offset` days away. By calendar day rather than
    /// 86,400 seconds, and re-normalised, so a clock change can't split a run —
    /// in a zone whose DST skips midnight, "start of day + 1 day" lands at 1am
    /// and would miss the set.
    private static func step(_ day: Date, by offset: Int, _ calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: offset, to: day).map(calendar.startOfDay(for:))
    }
}
