//
//  PracticeProgressStore.swift
//  Soulfull Gatherings
//
//  The app's view of what this member has practiced — read from the
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

/// What `PracticeProgressStore` reads and writes through. `live` is the app's;
/// tests hand in their own (`SoulfullTests/Practice/PracticeProgressStoreTests`).
struct PracticeProgressBackend {
    var currentUserID: @MainActor () -> UUID?
    var fetchProgress: @MainActor (_ userID: UUID) async throws -> [PracticeProgress]
    var fetchLedger: @MainActor (_ userID: UUID) async throws -> [PracticePlayRecord]
    var recordPlay: @MainActor (_ play: PracticePlay, _ userID: UUID, _ secondsPlayed: Int,
                                _ positionSeconds: Int, _ completed: Bool) async throws -> Void
    var now: @MainActor () -> Date
    /// Where a member's writes that didn't land wait between launches
    /// (`PendingPlayWrites`, as JSON). Nothing is kept by default.
    var loadPending: @MainActor (_ member: UUID) -> String? = { _ in nil }
    var savePending: @MainActor (_ member: UUID, _ json: String?) -> Void = { _, _ in }

    /// Computed rather than stored, so there is no shared global to make
    /// `Sendable`.
    static var live: PracticeProgressBackend {
        PracticeProgressBackend(
            currentUserID: { SupabaseService.shared.client.auth.currentUser?.id },
            fetchProgress: { try await SupabaseService.shared.fetchPracticeProgress(userID: $0) },
            fetchLedger: { try await SupabaseService.shared.fetchPracticeLedger(userID: $0) },
            recordPlay: { play, userID, seconds, position, completed in
                try await SupabaseService.shared.recordPracticePlay(play, userID: userID,
                                                                    secondsPlayed: seconds,
                                                                    positionSeconds: position,
                                                                    completed: completed)
            },
            now: { Date.now },
            loadPending: { LocalUserStore.shared.string(forKey: PendingPlayWrites.storageKey, member: $0) },
            savePending: { LocalUserStore.shared.set($1, forKey: PendingPlayWrites.storageKey, member: $0) }
        )
    }
}

@Observable @MainActor
final class PracticeProgressStore {

    static let shared = PracticeProgressStore()

    private let backend: PracticeProgressBackend

    init(backend: PracticeProgressBackend = .live) {
        self.backend = backend
    }

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
    private var userID: UUID? { backend.currentUserID() }

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
        // First, so what reaches the server now is in what is read back.
        await retryPending()
        async let progressLoad: Void = refreshProgress(for: userID, force: force)
        async let ledgerLoad: Void = refreshLedger(for: userID, force: false)
        _ = await (progressLoad, ledgerLoad)
    }

    /// Everything, from the server — pull to refresh on the You tab, which is
    /// where a sitting recorded on another device would otherwise stay
    /// invisible until the next launch.
    func reloadAll() async {
        guard let userID else { clear(); return }
        await retryPending()
        async let progressLoad: Void = refreshProgress(for: userID, force: true)
        async let ledgerLoad: Void = refreshLedger(for: userID, force: true)
        _ = await (progressLoad, ledgerLoad)
    }

    private func refreshProgress(for userID: UUID, force: Bool) async {
        guard force || loadedFor != userID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await backend.fetchProgress(userID)
            // The session can change while this reads (see `refreshLedger`):
            // one member's Continue card must not land on the next person's
            // Home.
            guard self.userID == userID else { return }
            // Never `uniqueKeysWithValues`, which traps on a repeated key: a
            // read that ever answered with one would crash every launch.
            progress = Dictionary(rows.map { ($0.id, $0) }) { first, second in
                first.lastPlayedAt >= second.lastPlayedAt ? first : second
            }
            loadedFor = userID
        } catch where error.isCancellation {
        } catch {
            // A missing table (before 0008 is applied) or a dropped connection
            // both mean "no history to show" — the Practice tab and Home simply
            // render as they did before progress existed.
            Log.data.info("Practice progress unavailable: \(error.localizedDescription)")
            if self.userID == userID, loadedFor != userID { progress = [:] }
        }
    }

    private func refreshLedger(for userID: UUID, force: Bool) async {
        guard force || ledgerLoadedFor != userID || ledgerStatus != .loaded else { return }
        do {
            let rows = try await backend.fetchLedger(userID)
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
            if self.userID == userID, ledgerLoadedFor != userID {
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
        finishedEvents.removeAll()
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

    // MARK: - Writing

    /// Records consumption against the ledger and folds the result into the
    /// local map so the UI updates without a round trip.
    ///
    /// Never throws: nothing about playback should stall or fail because a
    /// write did. A write that can't land now waits on the phone and is sent
    /// again (`PendingPlayWrites`): it used to be logged and dropped, so a
    /// journal written on a plane showed as done, then left the streak and
    /// history at the next launch and never credited its guide.
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
        // Anything of this play's still waiting rides along: a finish that
        // failed to land is carried by the next heartbeat.
        let write = pending(for: owner).merged(
            PendingPlayWrites.Write(play, owner: owner, secondsPlayed: secondsPlayed,
                                    positionSeconds: positionSeconds, completed: completed,
                                    since: backend.now()))
        // A write that landed means the connection is back for the rest too.
        if await send(write) { await retryPending() }
    }

    /// Sends what is waiting for this member, oldest first, stopping at the
    /// first that still can't land. Called on every `refresh`, after a write
    /// lands, and when the app comes back to the foreground.
    func retryPending() async {
        guard let userID, !isRetryingPending else { return }
        isRetryingPending = true
        defer { isRetryingPending = false }
        var queue = pending(for: userID)
        let due = queue.due(for: userID, now: backend.now())
        savePending(queue, for: userID)
        for write in due {
            guard self.userID == userID, await send(write) else { return }
        }
    }

    /// Hands one write to the ledger. False when it couldn't land and is
    /// waiting — the rest won't land either, so a retry stops there.
    private func send(_ write: PendingPlayWrites.Write) async -> Bool {
        guard let play = write.play else {
            updatePending(for: write.owner) { $0.remove(write.eventID) }
            return true
        }
        do {
            try await backend.recordPlay(play, write.owner, write.secondsPlayed,
                                         write.positionSeconds, write.completed)
            updatePending(for: write.owner) { $0.settle(write) }
            return true
        } catch where PendingPlayWrites.isWorthRetrying(error) {
            Log.data.error("Couldn't record practice play, will retry: \(error.localizedDescription)")
            updatePending(for: write.owner) { $0.hold(write) }
            return false
        } catch {
            // The database itself said no (not a practice, a closed row), and
            // it will say so again.
            Log.data.error("Practice play refused: \(error.localizedDescription)")
            updatePending(for: write.owner) { $0.remove(write.eventID) }
            return true
        }
    }

    @ObservationIgnored private var isRetryingPending = false

    private func pending(for member: UUID) -> PendingPlayWrites {
        guard let json = backend.loadPending(member),
              let queue = try? JSONDecoder().decode(PendingPlayWrites.self, from: Data(json.utf8))
        else { return PendingPlayWrites() }
        return queue
    }

    private func savePending(_ queue: PendingPlayWrites, for member: UUID) {
        let json = queue.isEmpty ? nil
            : (try? JSONEncoder().encode(queue)).flatMap { String(data: $0, encoding: .utf8) }
        backend.savePending(member, json)
    }

    private func updatePending(for member: UUID, _ change: (inout PendingPlayWrites) -> Void) {
        var queue = pending(for: member)
        change(&queue)
        savePending(queue, for: member)
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

        // Finished when this play first says so — the server stamps
        // `completed_at` once, at that moment, and later heartbeats of the
        // same play don't move it. An open that doesn't finish keeps the
        // finish from before.
        let now = backend.now()
        var lastCompletedAt = existing?.lastCompletedAt
        if completed, !finishedEvents.contains(play.eventID) {
            finishedEvents.insert(play.eventID)
            lastCompletedAt = now
        }

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
            lastPlayedAt: now,
            lastCompletedAt: lastCompletedAt
        )
    }

    /// Seconds already folded into the optimistic mirror for an in-flight play.
    /// Bounded by the number of practices opened in one app session.
    private var foldedSeconds: [UUID: Int] = [:]
    /// Plays already folded in as finished, so their finish keeps its moment.
    private var finishedEvents: Set<UUID> = []

    /// Mirrors the ledger row this heartbeat upserts, applying the same rules
    /// the DB trigger does — seconds never go backwards and are clamped to the
    /// practice's length, completion latches, `started_at` is fixed by the
    /// first write — so finishing a practice moves the streak and the class
    /// count at once, not at the next launch.
    private func applyToLedger(_ play: PracticePlay, secondsPlayed: Int, completed: Bool) {
        let existing = ledger[play.eventID]
        var seconds = max(secondsPlayed, existing?.secondsPlayed ?? 0)
        if let duration = play.durationSeconds { seconds = min(seconds, duration) }
        let now = backend.now()
        ledger[play.eventID] = PracticePlayRecord(
            eventID: play.eventID,
            kind: play.kind,
            secondsPlayed: seconds,
            completed: completed || (existing?.completed ?? false),
            startedAt: existing?.startedAt ?? now,
            // Stamped once, when it first finishes — as the server stamps it.
            completedAt: existing?.completedAt ?? (completed ? now : nil)
        )
    }
}

// MARK: - Writes waiting to land

/// Ledger writes that didn't reach the server, kept on the phone until they
/// do — one per play, the latest of its heartbeats with anything earlier
/// folded in. Stored in the member's own namespace (`LocalUserStore`), so
/// deleting the account deletes them and another member never sends them.
///
/// A write waits a day at most. The server closes a play a day after it
/// begins (0029), and dates a play it has never seen by when it arrives: past
/// a day, a practice would land on the wrong day, or in a month already paid.
struct PendingPlayWrites: Codable, Equatable {

    static let storageKey = "practice.pendingPlays"
    static let lifetime: TimeInterval = 24 * 3600
    /// Bounded, so a phone offline for a long time can't grow it without end.
    static let capacity = 100

    struct Write: Codable, Equatable {
        let eventID: UUID
        let owner: UUID
        /// Raw, so a write keeps decoding whatever the next build calls things.
        let kind: String
        let contentID: Int
        let title: String
        let creator: String?
        let category: String?
        let durationSeconds: Int?
        var secondsPlayed: Int
        var positionSeconds: Int
        var completed: Bool
        /// When this play first failed to land.
        var since: Date

        init(_ play: PracticePlay, owner: UUID, secondsPlayed: Int,
             positionSeconds: Int, completed: Bool, since: Date) {
            eventID = play.eventID
            self.owner = owner
            kind = play.kind.rawValue
            contentID = play.contentID
            title = play.title
            creator = play.creator
            category = play.category?.rawValue
            durationSeconds = play.durationSeconds
            self.secondsPlayed = secondsPlayed
            self.positionSeconds = positionSeconds
            self.completed = completed
            self.since = since
        }

        var play: PracticePlay? {
            PracticeContentKind(rawValue: kind).map { kind in
                PracticePlay(kind: kind, contentID: contentID, title: title, creator: creator,
                             category: category.flatMap(PracticeCategory.init(rawValue:)),
                             durationSeconds: durationSeconds, eventID: eventID)
            }
        }
    }

    private(set) var writes: [UUID: Write] = [:]

    var isEmpty: Bool { writes.isEmpty }

    /// `write`, with what is still waiting for the same play folded in: the
    /// most seconds, and a finish that never un-finishes — as the server keeps
    /// them. The position is the newest.
    func merged(_ write: Write) -> Write {
        guard let waiting = writes[write.eventID] else { return write }
        var next = write
        next.secondsPlayed = max(write.secondsPlayed, waiting.secondsPlayed)
        next.completed = write.completed || waiting.completed
        next.since = min(write.since, waiting.since)
        return next
    }

    /// Keeps a write that couldn't land, dropping the oldest past `capacity`.
    mutating func hold(_ write: Write) {
        writes[write.eventID] = merged(write)
        while writes.count > Self.capacity,
              let oldest = writes.values.min(by: { $0.since < $1.since }) {
            writes[oldest.eventID] = nil
        }
    }

    /// The server has `sent`. What was waiting for that play goes, unless it
    /// carried more than `sent` did.
    mutating func settle(_ sent: Write) {
        guard let waiting = writes[sent.eventID] else { return }
        if waiting.secondsPlayed <= sent.secondsPlayed, sent.completed || !waiting.completed {
            writes[sent.eventID] = nil
        }
    }

    mutating func remove(_ eventID: UUID) {
        writes[eventID] = nil
    }

    /// What is waiting for `owner`, oldest first. Anything past `lifetime` is
    /// dropped on the way.
    mutating func due(for owner: UUID, now: Date) -> [Write] {
        writes = writes.filter { now.timeIntervalSince($0.value.since) < Self.lifetime }
        return writes.values.filter { $0.owner == owner }.sorted { $0.since < $1.since }
    }

    /// Whether a write that failed this way can still land: anything but the
    /// database refusing it, which it would do again (`isDatabaseRefusal`).
    static func isWorthRetrying(_ error: any Error) -> Bool {
        !error.isDatabaseRefusal
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
    /// Whether anything was practiced today at all, finished or not. Not the
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
            // A practice day is the day it was FINISHED: a sitting begun before
            // midnight and finished after it keeps today, not yesterday. Rows
            // from before 0029 have no finish time, and their start stands in.
            let started = calendar.startOfDay(for: play.startedAt)
            let finished = play.completedAt.map(calendar.startOfDay(for:)) ?? started
            if started == today || (play.completed && finished == today) { touchedToday = true }
            if play.completed { days.insert(finished) }
            guard play.kind.countsAsClass else { continue }
            if play.completed { classes += 1 }
            seconds += max(0, play.secondsPlayed)
        }
        classesTaken = classes
        minutesPracticed = seconds / 60

        let streak = PracticeStreak(days: days, calendar: calendar, now: now)
        keptToday = streak.keptToday
        practicedToday = touchedToday
        currentStreak = streak.current
        bestStreak = streak.best
    }

    /// The one line on the streak tile that says what to do next. All of it
    /// reads off real history — nothing here is a nudge for its own sake.
    ///
    /// Telling someone who opened a prompt and didn't write, or stopped a
    /// session short, to "practice today" contradicts what they just did;
    /// what's true is that a practice needs finishing — and the words name the
    /// practice and the streak outright ("finish one" left people asking one
    /// what).
    var streakCaption: String {
        if keptToday { return "You've completed a practice today" }
        if currentStreak > 0 {
            return practicedToday ? "Finish a practice today to keep your streak"
                                  : "Practice today to keep your streak"
        }
        return "Finish a practice today to start your streak"
    }
}

/// The streak rule, apart from where the days come from: a member's own
/// ledger (`PracticeStats`), or a friend's latest run as the server hands it
/// over (`FriendPractice`, 0034, which counts days by the same rule in SQL).
struct PracticeStreak: Equatable {
    /// Consecutive practice days up to today — or up to yesterday, because
    /// today isn't over yet and a streak isn't lost until it is.
    let current: Int
    /// The longest run ever, the current one included.
    let best: Int
    /// Today is one of the days.
    let keptToday: Bool

    init(current: Int, best: Int, keptToday: Bool) {
        self.current = current
        self.best = best
        self.keptToday = keptToday
    }

    /// `days` are the starts of the local days on which a practice was
    /// finished, in `calendar`.
    init(days: Set<Date>, calendar: Calendar, now: Date) {
        let today = calendar.startOfDay(for: now)
        keptToday = days.contains(today)
        current = Self.run(endingOn: today, in: days, calendar: calendar)
            ?? Self.step(today, by: -1, calendar)
                .flatMap { Self.run(endingOn: $0, in: days, calendar: calendar) }
            ?? 0

        // Longest run: walk forward from every day that starts one.
        var longest = 0
        for day in days {
            guard let previous = Self.step(day, by: -1, calendar),
                  !days.contains(previous) else { continue }
            var length = 0
            var cursor: Date? = day
            while let current = cursor, days.contains(current) {
                length += 1
                cursor = Self.step(current, by: 1, calendar)
            }
            longest = max(longest, length)
        }
        best = max(longest, current)
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
    static func step(_ day: Date, by offset: Int, _ calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: offset, to: day).map(calendar.startOfDay(for:))
    }
}
