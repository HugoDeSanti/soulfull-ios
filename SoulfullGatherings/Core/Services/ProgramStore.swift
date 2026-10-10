//
//  ProgramStore.swift
//  Soulfull Gatherings
//
//  A member's standing with the digital programs: what they have joined, which
//  days they have finished, and — the part everything else hangs off — whether
//  a given day can be opened yet.
//
//  THE UNLOCK RULE, in one place so it can't drift:
//
//      Day 1 opens when you enrol.
//      Day N+1 opens when BOTH hold:
//        (a) every activity in Day N is complete, and
//        (b) the local calendar date has moved past the date Day N was
//            finished on.
//
//  (b) is why this isn't simply a checklist. A program is paced; finishing
//  Thursday's practices at 9pm does not hand you Friday's at 9:01.
//
//  Membership state lives in its own two tables rather than in `practice_plays`.
//  That ledger is what creator payouts are drawn from — append-mostly, no
//  delete policy — and a program day is not a payable event. The activities
//  *inside* a day still record to it exactly as they do from the Practice tab,
//  so a creator is paid the same either way. See CLAUDE.md → Digital programs.
//

import SwiftUI

@Observable @MainActor
final class ProgramStore {

    static let shared = ProgramStore()

    /// Keyed by program id.
    private(set) var enrollments: [String: ProgramEnrollment] = [:]
    /// program id → day number → the moment the server recorded it.
    private(set) var completions: [String: [Int: Date]] = [:]
    private(set) var isLoading = false
    /// Whose state is loaded, so a session change forces a reload instead of
    /// showing the previous member's programs.
    private(set) var loadedFor: UUID?
    /// Whether `enrollments` is an answer or a shrug. The tab can treat a
    /// failed read as "nothing joined" — it renders the catalog either way —
    /// but the You tab lists what was joined and must not call a dropped
    /// connection an empty history.
    private(set) var status: HistoryLoadStatus = .notLoaded

    /// Sessions referenced by a curriculum, resolved on demand. Keyed by
    /// `practice_sessions.id`.
    private var sessionCache: [Int: PracticeSession] = [:]
    /// Ids already looked up and *not* found, so a curriculum pointing at media
    /// that hasn't been uploaded doesn't re-query on every appearance.
    private var missingSessionIDs: Set<Int> = []

    /// Read from the live session rather than threaded through the view tree —
    /// same reasoning as `PracticeProgressStore`.
    private var userID: UUID? { SupabaseService.shared.client.auth.currentUser?.id }

    var currentUserID: UUID? { userID }

    // MARK: - Loading

    func refresh(force: Bool = false) async {
        guard let userID else { clear(); return }
        guard force || loadedFor != userID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let enrolled = SupabaseService.shared.fetchProgramEnrollments(userID: userID)
            async let days = SupabaseService.shared.fetchProgramDayCompletions(userID: userID)
            let (rows, dayRows) = try await (enrolled, days)
            enrollments = Dictionary(uniqueKeysWithValues: rows.map { ($0.programID, $0) })
            var byProgram: [String: [Int: Date]] = [:]
            for row in dayRows { byProgram[row.programID, default: [:]][row.day] = row.completedAt }
            completions = byProgram
            loadedFor = userID
            status = .loaded
        } catch where error.isCancellation {
        } catch {
            // Missing tables (before 0013) or no connection both mean "nothing
            // joined" — the tab renders as a plain catalog, which is correct.
            Log.data.info("Program state unavailable: \(error.localizedDescription)")
            if loadedFor != userID {
                enrollments = [:]
                completions = [:]
                status = .unavailable(offline: error.isOffline)
            }
        }
    }

    /// Drops everything in memory. Called on sign-out and account deletion so
    /// the next member never sees the previous one's week.
    func clear() {
        enrollments = [:]
        completions = [:]
        loadedFor = nil
        status = .notLoaded
        sessionCache = [:]
        missingSessionIDs = []
    }

    #if DEBUG
    /// `-preview-you` only: fixture enrolments in place of the member's own,
    /// marked loaded for this session so a `refresh` can't replace them.
    func installPreview(enrollments: [ProgramEnrollment], completions: [ProgramDayCompletion]) {
        self.enrollments = Dictionary(uniqueKeysWithValues: enrollments.map { ($0.programID, $0) })
        var byProgram: [String: [Int: Date]] = [:]
        for row in completions { byProgram[row.programID, default: [:]][row.day] = row.completedAt }
        self.completions = byProgram
        loadedFor = userID
        status = .loaded
    }
    #endif

    // MARK: - Reading

    func isEnrolled(_ programID: String) -> Bool { enrollments[programID] != nil }
    func enrollment(_ programID: String) -> ProgramEnrollment? { enrollments[programID] }
    func completedDayCount(_ programID: String) -> Int { completions[programID]?.count ?? 0 }

    /// How far through the program, 0–1. Zero for a program not started.
    func fractionComplete(_ program: Program) -> Double {
        let total = program.authoredDays.count
        guard total > 0 else { return 0 }
        return min(1, Double(completedDayCount(program.id)) / Double(total))
    }

    /// The day the member is on — the lowest one not yet finished. Nil once the
    /// whole program is done.
    func currentDay(_ program: Program) -> ProgramDay? {
        program.authoredDays.first { completions[program.id]?[$0.day] == nil }
    }

    var allComplete: Set<String> {
        Set(enrollments.values.filter { $0.completedAt != nil }.map(\.programID))
    }

    /// When a given day became (or becomes) available — see
    /// `ProgramUnlockRule.unlockedAt`.
    func dayUnlockedAt(_ program: Program, day: Int) -> Date? {
        ProgramUnlockRule.unlockedAt(day: day,
                                     enrolledAt: enrollments[program.id]?.enrolledAt,
                                     completions: completions[program.id] ?? [:],
                                     calendar: .current)
    }

    func state(_ program: Program, day: Int) -> ProgramDayState {
        ProgramUnlockRule.state(day: day,
                                enrolledAt: enrollments[program.id]?.enrolledAt,
                                completions: completions[program.id] ?? [:],
                                // Through the clock so a day opening overnight
                                // re-renders whatever showed it locked.
                                now: AppClock.shared.now,
                                calendar: .current)
    }

    /// Whether one activity counts as done **for this day** — see
    /// `ProgramUnlockRule.counts`.
    func isDone(_ activity: ProgramActivity, in program: Program, day: Int) -> Bool {
        ProgramUnlockRule.counts(PracticeProgressStore.shared.progress(kind: activity.kind,
                                                                      contentID: activity.contentID),
                                 towardDayUnlockedAt: dayUnlockedAt(program, day: day))
    }

    func doneCount(of day: ProgramDay, in program: Program) -> Int {
        resolved(day, in: program).filter { isDone($0.activity, in: program, day: day.day) }.count
    }

    // MARK: - Resolving a curriculum to real content

    /// Looks up everything a program references, so its days can be rendered:
    /// the written libraries (shared, and cached) and every session. Cheap to
    /// call repeatedly — only unseen session ids hit the network.
    func resolveContent(for program: Program) async {
        await WrittenPracticeStore.shared.refresh()
        let ids = Set(program.authoredDays
            .flatMap(\.activities)
            .filter { $0.kind == .session }
            .map(\.contentID))
        let wanted = ids.subtracting(sessionCache.keys).subtracting(missingSessionIDs)
        guard !wanted.isEmpty else { return }
        do {
            let sessions = try await SupabaseService.shared.fetchPracticeSessions(ids: Array(wanted))
            for session in sessions { sessionCache[session.id] = session }
            // Remember the misses too, so an unseeded reference costs one query
            // rather than one per appearance.
            let found = Set(sessions.map(\.id))
            let absent = wanted.subtracting(found)
            if !absent.isEmpty {
                missingSessionIDs.formUnion(absent)
                Log.data.error("Program \(program.id, privacy: .public) references sessions that don't exist: \(absent.sorted().map(String.init).joined(separator: ", "), privacy: .public)")
            }
        } catch where error.isCancellation {
        } catch {
            Log.data.info("Couldn't resolve program sessions: \(error.localizedDescription)")
        }
    }

    /// A day's activities, paired with the content they point at — see
    /// `ProgramDayResolution` for what is dropped and what is waited on.
    func resolution(_ day: ProgramDay) -> ProgramDayResolution {
        ProgramDayResolution(day, lookup: lookup)
    }

    func resolved(_ day: ProgramDay, in program: Program) -> [ResolvedActivity] {
        resolution(day).activities
    }

    private func lookup(_ activity: ProgramActivity) -> ActivityLookup {
        let id = activity.contentID
        switch activity.kind {
        case .session:
            if let session = sessionCache[id] { return .found(.session(session)) }
            return missingSessionIDs.contains(id) ? .missing : .pending
        case .journal:
            return written(WrittenPracticeStore.shared.library.journal(id: id).map(ProgramActivityContent.journal))
        case .exercise:
            return written(WrittenPracticeStore.shared.library.exercise(id: id).map(ProgramActivityContent.exercise))
        case .recipe:
            return written(WrittenPracticeStore.shared.library.recipe(id: id).map(ProgramActivityContent.recipe))
        }
    }

    /// A written practice is missing only once this launch has read the
    /// tables; before that it may just be newer than the remembered copy.
    private func written(_ content: ProgramActivityContent?) -> ActivityLookup {
        if let content { return .found(content) }
        return WrittenPracticeStore.shared.isAuthoritative ? .missing : .pending
    }

    // MARK: - Writing

    /// Joins a program. Caller must already have gated on `auth.hasAccount` —
    /// the RLS policies refuse an anonymous guest, and this would surface as a
    /// bare failure rather than the account sheet the member deserves.
    func enroll(in program: Program) async throws {
        guard let userID else { throw AppError.unknown }
        let enrollment = try await SupabaseService.shared.enrollInProgram(id: program.id, userID: userID)
        if loadedFor != userID {
            // Nothing of this member's has been read yet — typically a guest
            // who signed in from "Start this digital retreat", which cleared the
            // store. Marking it loaded here, with no day completions in it, used
            // to show a member already part-way through as starting from Day 1
            // (re-celebrating days done weeks ago) and their other programs as
            // not joined, for the rest of the session. Read everything instead.
            await refresh(force: true)
        }
        // Whatever that read said, the enrolment just written stands.
        enrollments[program.id] = enrollment
        // Deliberately NOT awaited. `requestAuthorizationIfNeeded` doesn't
        // return until the member answers the system dialog, and awaiting it
        // here would hold the push to day 1 behind a prompt about something
        // that hasn't happened yet.
        Task { await ProgramNotifications.requestAuthorizationIfNeeded() }
    }

    /// Leaves a program: the enrolment and its day completions. Practice
    /// history is untouched — those practices were really done.
    func leave(_ program: Program) async throws {
        guard let userID else { throw AppError.unknown }
        try await SupabaseService.shared.leaveProgram(id: program.id, userID: userID)
        enrollments[program.id] = nil
        completions[program.id] = nil
        ProgramNotifications.cancel(programID: program.id)
    }

    /// Checks whether the open day is finished, and records it if so.
    ///
    /// Returns the day number when this call is the one that completed it, so
    /// the caller can celebrate exactly once. Safe to call on every appearance:
    /// it no-ops unless the open day's activities have all just been done.
    @discardableResult
    func syncCompletion(for program: Program) async -> Int? {
        guard userID != nil, isEnrolled(program.id) else { return nil }
        guard let day = currentDay(program) else {
            await markFinishedIfNeeded(program)
            return nil
        }
        guard state(program, day: day.day).isOpen else { return nil }

        let resolution = resolution(day)
        guard resolution.isFinished(isDone: { isDone($0, in: program, day: day.day) }) else { return nil }
        if resolution.activities.isEmpty {
            // A day that resolves to nothing is a broken curriculum. Completing
            // it is the lesser evil: the alternative traps the member on it
            // forever, with no action available that could ever free them.
            Log.data.error("Program \(program.id, privacy: .public) day \(day.day, privacy: .public) has no resolvable activities — completing it so the program isn't stuck")
        }
        return await record(day: day, in: program)
    }

    private func record(day: ProgramDay, in program: Program) async -> Int? {
        guard let userID else { return nil }
        do {
            let at = try await SupabaseService.shared.completeProgramDay(
                programID: program.id, day: day.day, userID: userID)
            completions[program.id, default: [:]][day.day] = at
            ProgramNotifications.cancel(programID: program.id, day: day.day)
            scheduleNextDayNudge(after: day, in: program, completedAt: at)
            await markFinishedIfNeeded(program)
            return day.day
        } catch {
            Log.data.error("Couldn't record program day: \(error.localizedDescription)")
            return nil
        }
    }

    /// Stamps the enrolment finished once every authored day is done.
    private func markFinishedIfNeeded(_ program: Program) async {
        guard let userID,
              let enrollment = enrollments[program.id],
              enrollment.completedAt == nil,
              !program.authoredDays.isEmpty,
              currentDay(program) == nil
        else { return }
        let now = Date.now
        do {
            try await SupabaseService.shared.markProgramCompleted(id: program.id, userID: userID, at: now)
            enrollments[program.id] = ProgramEnrollment(programID: program.id,
                                                        enrolledAt: enrollment.enrolledAt,
                                                        completedAt: now)
        } catch {
            Log.data.error("Couldn't mark program complete: \(error.localizedDescription)")
        }
    }

    private func scheduleNextDayNudge(after day: ProgramDay, in program: Program, completedAt: Date) {
        guard let next = program.authoredDays.first(where: { $0.day == day.day + 1 }) else { return }
        let calendar = Calendar.current
        guard let unlock = calendar.date(byAdding: .day, value: 1,
                                         to: calendar.startOfDay(for: completedAt))
        else { return }
        ProgramNotifications.schedule(programID: program.id,
                                      programTitle: program.title,
                                      day: next.day,
                                      dayTitle: next.title,
                                      unlockAt: unlock)
    }
}

// MARK: - The unlock rule

/// The unlock rule itself, as pure functions of a member's enrolment and
/// completions, the calendar and the time. `ProgramStore` supplies the live
/// values; keeping the rule apart from them is what lets
/// `SoulfullTests/ProgramUnlockRuleTests` pin it down without a session, a
/// network or a clock.
enum ProgramUnlockRule {

    /// When a given day became (or becomes) available.
    ///
    /// Day 1 is the enrolment moment. Every later day is **the next local
    /// midnight after the previous day was finished** — which is what "the date
    /// has changed" means. `startOfDay` + 1 day rather than +86400 seconds, so
    /// the clocks going forward or back doesn't shift the boundary.
    ///
    /// Nil means the chain is broken further back: not enrolled, or the
    /// previous day isn't finished.
    static func unlockedAt(day: Int, enrolledAt: Date?, completions: [Int: Date],
                           calendar: Calendar) -> Date? {
        guard let enrolledAt else { return nil }
        guard day > 1 else { return enrolledAt }
        guard let previous = completions[day - 1] else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: previous))
    }

    static func state(day: Int, enrolledAt: Date?, completions: [Int: Date],
                      now: Date, calendar: Calendar) -> ProgramDayState {
        if let finished = completions[day] { return .complete(finished) }
        guard let unlock = unlockedAt(day: day, enrolledAt: enrolledAt,
                                      completions: completions, calendar: calendar)
        else { return .awaitingPreviousDay }
        return now >= unlock ? .open : .opens(unlock)
    }

    /// Whether a practice's progress counts toward a day that unlocked at
    /// `unlocked`.
    ///
    /// ⚠️ The `lastPlayedAt >= unlocked` half is load-bearing and easy to drop
    /// as redundant. `practice_progress.completed` is latched for all time, so
    /// without it a member with any history at all would have days 1–4 marked
    /// finished the instant they enrolled and the pacing — the whole point —
    /// would evaporate. The visible consequence is intentional: the same prompt
    /// can appear on day 2 and day 6, and must be genuinely re-done the second
    /// time.
    static func counts(_ progress: PracticeProgress?, towardDayUnlockedAt unlocked: Date?) -> Bool {
        guard let unlocked, let progress else { return false }
        return progress.completed && progress.lastPlayedAt >= unlocked
    }
}

// MARK: - Resolving a day

/// What a curriculum entry points at, as far as is known right now.
enum ActivityLookup: Hashable {
    case found(ProgramActivityContent)
    /// Looked for and not there — unpublished, or never uploaded.
    case missing
    /// Not known yet: its library hasn't been read this launch, or the read
    /// failed.
    case pending
}

/// A day's activities against what can be found of them, as a pure function
/// of a lookup — `ProgramStore` supplies the live one, and
/// `SoulfullTests/ProgramDayResolutionTests` its own.
///
/// **A missing activity is dropped**, not rendered as a broken row. A
/// curriculum may reference media before it is uploaded, and an activity that
/// can't be opened can't be completed — which, under the unlock rule, would
/// stall the member's program permanently. So a day quietly shrinks to what
/// exists and grows again when the content lands.
///
/// ⚠️ **A pending one is not dropped from the judgement.** It is left out of
/// what can be shown, but the day can't be finished around it: it is almost
/// certainly there, and the completion is latched. Before the written
/// libraries moved to tables they could never be pending, and a session
/// whose read had failed was treated as missing — so a day could close with a
/// practice nobody had been shown.
struct ProgramDayResolution {
    /// What can be shown and opened, in curriculum order.
    let activities: [ResolvedActivity]
    /// Every activity has an answer, found or missing.
    let isSettled: Bool

    init(_ day: ProgramDay, lookup: (ProgramActivity) -> ActivityLookup) {
        var activities: [ResolvedActivity] = []
        var settled = true
        for activity in day.activities {
            switch lookup(activity) {
            case .found(let content): activities.append(ResolvedActivity(activity: activity, content: content))
            case .missing:            break
            case .pending:            settled = false
            }
        }
        self.activities = activities
        isSettled = settled
    }

    /// Whether the day is finished: settled, and everything that remains is
    /// done. A settled day with nothing left in it counts — see
    /// `ProgramStore.syncCompletion`.
    func isFinished(isDone: (ProgramActivity) -> Bool) -> Bool {
        isSettled && activities.allSatisfy { isDone($0.activity) }
    }
}

// MARK: - Resolved activity

/// A curriculum entry paired with the content it points at.
struct ResolvedActivity: Identifiable, Hashable {
    let activity: ProgramActivity
    let content: ProgramActivityContent

    var id: String { activity.id }
    var note: String? { activity.note }
}

/// The content behind a program activity, in whichever library it lives.
enum ProgramActivityContent: Hashable {
    case session(PracticeSession)
    case journal(JournalPrompt)
    case exercise(Exercise)
    case recipe(Recipe)

    var title: String {
        switch self {
        case .session(let s):  s.title
        case .journal(let p):  p.title
        case .exercise(let e): e.title
        case .recipe(let r):   r.title
        }
    }

    /// The library this came from, as the member would name it.
    var libraryLabel: String {
        switch self {
        case .session(let s):  s.category.title
        case .journal:         "Journal"
        case .exercise(let e): e.focus
        case .recipe:          "Recipe"
        }
    }

    var systemImage: String {
        switch self {
        case .session(let s):  s.mediaKind.systemImage
        case .journal:         "pencil.and.scribble"
        case .exercise:        "figure.strengthtraining.functional"
        case .recipe:          "fork.knife"
        }
    }

    var imageUrl: String {
        switch self {
        case .session(let s):  s.imageUrl
        case .journal(let p):  p.imageUrl
        case .exercise(let e): e.imageUrl
        case .recipe(let r):   r.imageUrl
        }
    }

    var durationLabel: String {
        switch self {
        case .session(let s):  s.durationLabel
        case .journal:         "A few minutes"
        case .exercise(let e): e.durationLabel
        case .recipe(let r):   "\(r.minutes) min"
        }
    }
}
