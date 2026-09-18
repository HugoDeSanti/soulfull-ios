//
//  ProfileViewModel.swift
//  Soulfull Gatherings
//
//  The member's own journeys, for the You tab: the digital retreats (programs)
//  they have joined and the in-person retreats they have been on.
//
//  The practice numbers are NOT here — they are `PracticeProgressStore.stats`,
//  because Home names the same streak and the two must never disagree.
//
//  Nothing is invented. A member with no history sees empty sections that say
//  so; a member we couldn't reach the server for is told that instead, because
//  "you haven't been on a retreat" and "we couldn't check" are not the same
//  sentence.
//

import SwiftUI

/// One program on the You tab, and where the member is in it.
struct ProgramJourney: Identifiable, Hashable {
    enum Standing: Hashable {
        /// `day` is the one they're on; `fraction` is days finished over days.
        case inProgress(day: Int, of: Int, fraction: Double)
        /// When the last day was finished. Nil only if the enrolment was
        /// stamped complete without day rows to date it by.
        case completed(Date?)
    }

    let program: Program
    let standing: Standing

    var id: String { program.id }
    var isCompleted: Bool { if case .completed = standing { return true }; return false }
}

/// Why a section of the You tab has nothing to show, when it isn't because
/// there's nothing to show.
enum ProfileLoadFailure: Equatable {
    case offline
    case failed

    init(offline: Bool) { self = offline ? .offline : .failed }

    var line: String {
        switch self {
        case .offline: "You're offline. Reconnect to see this."
        case .failed:  "We couldn't load this just now."
        }
    }
}

@Observable @MainActor
final class ProfileViewModel {

    /// Every program this member has joined, published or not.
    private(set) var programs: [Program] = []
    /// Retreats with a paid booking whose last day has passed, most recent
    /// first. Empty for everyone while `AppFeatures.paymentsEnabled` is off,
    /// unless the team records a booking by hand.
    private(set) var retreats: [Retreat] = []
    private(set) var programsFailure: ProfileLoadFailure?
    private(set) var retreatsFailure: ProfileLoadFailure?
    /// Per section, so each can show its own spinner rather than one for both.
    private(set) var programsLoaded = false
    private(set) var retreatsLoaded = false

    private let store = ProgramStore.shared
    private var loadedFor: UUID?

    /// `-preview-you`: renders the member layout against fixtures, so the
    /// populated screen can be worked on (and tested) without an account.
    /// Always false in Release.
    static var isPreview: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-preview-you")
        #else
        false
        #endif
    }

    // MARK: - Loading

    /// Loads the member's practice, programs and retreats. Cheap on appear —
    /// each piece no-ops when this member's data is already in hand. `force`
    /// is pull to refresh: everything, from the server.
    func load(force: Bool = false) async {
        #if DEBUG
        if Self.isPreview { installPreviewFixture(); return }
        #endif
        guard let userID = store.currentUserID else { reset(); return }
        if loadedFor != userID { reset() }

        async let practice: Void = force
            ? PracticeProgressStore.shared.reloadAll()
            : PracticeProgressStore.shared.refresh()
        async let joined: Void = loadPrograms(for: userID, force: force)
        async let visited: Void = loadRetreats(for: userID, force: force)
        _ = await (practice, joined, visited)
        if store.currentUserID == userID { loadedFor = userID }
    }

    private func loadPrograms(for userID: UUID, force: Bool) async {
        await store.refresh(force: force)
        guard store.currentUserID == userID else { return }
        if case .unavailable(let offline) = store.status {
            programsFailure = ProfileLoadFailure(offline: offline)
            programsLoaded = true
            return
        }

        let ids = Set(store.enrollments.keys)
        guard force || ids != Set(programs.map(\.id)) || !programsLoaded else { return }
        do {
            let fetched = try await SupabaseService.shared.fetchPrograms(ids: Array(ids))
            guard store.currentUserID == userID else { return }
            programs = fetched
            programsFailure = nil
        } catch where error.isCancellation {
            return
        } catch {
            Log.data.info("Joined programs unavailable: \(error.localizedDescription)")
            if programs.isEmpty { programsFailure = ProfileLoadFailure(offline: error.isOffline) }
        }
        programsLoaded = true
    }

    private func loadRetreats(for userID: UUID, force: Bool) async {
        guard force || !retreatsLoaded || retreatsFailure != nil else { return }
        do {
            let bookings = try await SupabaseService.shared.fetchPaidBookings(userID: userID)
            let ids = Array(Set(bookings.map(\.retreatId)))
            let fetched = try await SupabaseService.shared.fetchRetreats(ids: ids)
            guard store.currentUserID == userID else { return }
            // A paid booking for a retreat still ahead is a trip, not a memory —
            // "experienced" means its last day is behind them.
            retreats = fetched
                .filter(\.hasEnded)
                .sorted { $0.startDate > $1.startDate }
            retreatsFailure = nil
        } catch where error.isCancellation {
            return
        } catch {
            Log.data.info("Past retreats unavailable: \(error.localizedDescription)")
            if retreats.isEmpty { retreatsFailure = ProfileLoadFailure(offline: error.isOffline) }
        }
        retreatsLoaded = true
    }

    private func reset() {
        programs = []
        retreats = []
        programsFailure = nil
        retreatsFailure = nil
        programsLoaded = false
        retreatsLoaded = false
        loadedFor = nil
    }

    // MARK: - Reading

    /// The joined programs, in progress first (most recently joined leading,
    /// as on the Programs tab), then completed (most recently finished first).
    var journeys: [ProgramJourney] {
        let all = programs.compactMap(journey(for:))
        let active = all.filter { !$0.isCompleted }.sorted {
            (store.enrollment($0.id)?.enrolledAt ?? .distantPast)
                > (store.enrollment($1.id)?.enrolledAt ?? .distantPast)
        }
        let finished = all.filter(\.isCompleted).sorted {
            finishedAt($0) > finishedAt($1)
        }
        return active + finished
    }

    private func journey(for program: Program) -> ProgramJourney? {
        guard let enrollment = store.enrollment(program.id) else { return nil }
        let done = store.completedDayCount(program.id)

        if let completedAt = enrollment.completedAt {
            return ProgramJourney(program: program, standing: .completed(completedAt))
        }
        // Every authored day finished, but the enrolment not stamped yet —
        // `syncCompletion` does that the next time the program is opened. Only
        // when there ARE authored days: an unreadable curriculum has none, and
        // "nothing left to do" is not the same as "finished".
        if program.isStartable, store.currentDay(program) == nil {
            return ProgramJourney(program: program, standing: .completed(lastDayFinished(program)))
        }
        let total = program.isStartable ? program.authoredDays.count : program.days
        let day = store.currentDay(program)?.day ?? min(done + 1, max(total, 1))
        let fraction = total > 0 ? min(1, Double(done) / Double(total)) : 0
        return ProgramJourney(program: program,
                              standing: .inProgress(day: day, of: total, fraction: fraction))
    }

    private func lastDayFinished(_ program: Program) -> Date? {
        store.completions[program.id]?.values.max()
    }

    private func finishedAt(_ journey: ProgramJourney) -> Date {
        if case .completed(let date) = journey.standing, let date { return date }
        return .distantPast
    }

    // MARK: - Preview fixture

    #if DEBUG
    /// Deterministic numbers, relative to today, so `ProfileTests` can assert
    /// exact values and a screenshot shows every state at once:
    ///
    /// - a 4-day current streak (today and the three days before), practised
    ///   today;
    /// - a 9-day best streak, a month back;
    /// - 13 classes (4 movement + 9 sessions) — a finished journal entry, a
    ///   finished recipe and an unfinished session are NOT classes;
    /// - 250 minutes (60 + 180 + the unfinished session's 10). Journal and
    ///   recipe time is not counted; unfinished class time is.
    ///
    /// Plus one program in progress, one completed, and two past retreats.
    ///
    /// `-preview-you-today <state>` changes only today, to reach each of the
    /// streak tile's four captions:
    /// - `finished` (the default) — as above: "You've completed a practice today".
    /// - `unfinished` — today's two practices left unfinished. Today no longer
    ///   counts, so the streak is the three days before it (3), classes 12,
    ///   minutes still 250 (time spent counts, finished or not): "Finish a
    ///   practice today to keep your streak" — never "Practice today", to
    ///   someone who just did.
    /// - `none` — nothing at all today; streak 3, classes 12, minutes 235:
    ///   "Practice today to keep your streak".
    /// - `lapsed` — nothing for the last four days either, so no streak; best
    ///   still 9, classes 9, minutes 190: "Finish a practice today to start
    ///   your streak".
    private func installPreviewFixture() {
        let args = CommandLine.arguments
        let todayState = args.firstIndex(of: "-preview-you-today")
            .flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "finished"
        let finishedToday = todayState == "finished"
        let practicedToday = finishedToday || todayState == "unfinished"
        let recentRun = todayState != "lapsed"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date {
            // Mid-morning, so the fixture lands on the same day whenever it runs.
            calendar.date(byAdding: .hour, value: 10,
                          to: calendar.date(byAdding: .day, value: offset, to: today)!)!
        }
        func play(_ kind: PracticeContentKind, _ offset: Int, seconds: Int, done: Bool = true) -> PracticePlayRecord {
            PracticePlayRecord(eventID: UUID(), kind: kind, secondsPlayed: seconds,
                               completed: done, startedAt: day(offset))
        }

        var ledger: [PracticePlayRecord] = []
        if practicedToday { ledger.append(play(.exercise, 0, seconds: 900, done: finishedToday)) }
        if recentRun { ledger += (1...3).map { play(.exercise, -$0, seconds: 900) } }
        ledger += (22...30).map { play(.session, -$0, seconds: 1200) }
        ledger.append(play(.session, -25, seconds: 600, done: false))
        if practicedToday { ledger.append(play(.journal, 0, seconds: 300, done: finishedToday)) }
        ledger.append(play(.recipe, -10, seconds: 400))
        ledger.append(play(.journal, -5, seconds: 20, done: false))
        PracticeProgressStore.shared.installPreviewLedger(ledger)

        let inProgress = Program.mock[0]
        let finished = Program(
            id: "morning-light", title: "Morning Light", lead: "Alma Guerra", days: 2,
            imageUrl: "retreat-images/kyoto-2026-05.jpg",
            blurb: "A gentle return to moving before the day starts asking.",
            curriculum: ProgramCurriculum(
                overview: nil,
                days: [
                    ProgramDay(day: 1, title: "Waking", intention: nil, imageUrl: nil,
                               activities: [.init(kind: .exercise, contentID: 1)]),
                    ProgramDay(day: 2, title: "Rising", intention: nil, imageUrl: nil,
                               activities: [.init(kind: .exercise, contentID: 2)]),
                ],
                closing: nil))
        store.installPreview(
            enrollments: [
                ProgramEnrollment(programID: inProgress.id, enrolledAt: day(-3), completedAt: nil),
                ProgramEnrollment(programID: finished.id, enrolledAt: day(-40), completedAt: day(-38)),
            ],
            completions: [
                ProgramDayCompletion(programID: inProgress.id, day: 1, completedAt: day(-3)),
                ProgramDayCompletion(programID: inProgress.id, day: 2, completedAt: day(-1)),
                ProgramDayCompletion(programID: finished.id, day: 1, completedAt: day(-39)),
                ProgramDayCompletion(programID: finished.id, day: 2, completedAt: day(-38)),
            ])
        programs = [inProgress, finished]

        func past(_ template: Retreat, monthsAgo: Int) -> Retreat {
            let start = calendar.date(byAdding: .month, value: -monthsAgo, to: today)!
            return Retreat(id: template.id, name: template.name, country: template.country,
                           startDate: start,
                           endDate: calendar.date(byAdding: .day, value: 5, to: start)!,
                           maxGuests: template.maxGuests, priceUsd: template.priceUsd,
                           tags: template.tags, blurb: template.blurb, imageUrl: template.imageUrl,
                           toneTop: template.toneTop, toneMid: template.toneMid,
                           toneBase: template.toneBase)
        }
        let kyoto = Retreat.mock.first { $0.name == "Kyoto" } ?? Retreat.mock[0]
        let sedona = Retreat.mock.first { $0.name == "Sedona" } ?? Retreat.mock[1]
        retreats = [past(kyoto, monthsAgo: 4), past(sedona, monthsAgo: 14)]

        programsLoaded = true
        retreatsLoaded = true
    }
    #endif
}
