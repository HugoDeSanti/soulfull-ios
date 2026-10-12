//
//  PracticeActivity.swift
//  Soulfull Gatherings
//
//  Measures how much of a practice was actually consumed, and heartbeats it to
//  `PracticeProgressStore` — which is what content-creator payouts are drawn
//  from, so the measurement matters more than it looks.
//
//  Two shapes, because the libraries differ:
//
//    • `PlaybackReporter` for audio/video. It counts MEDIA time, not wall-clock
//      and not the scrubber position: seeking to the end of a track banks
//      nothing, and a paused player accrues nothing. Nor does seeking to the
//      end finish it — that takes having heard most of it.
//    • `.practiceActivity(_:)` for the written libraries (journal, movement,
//      recipes), which have no transport — there, time on screen is the only
//      honest signal available.
//
//  Both heartbeat periodically rather than only on exit, so a practice
//  interrupted by a phone call or a force-quit still credits its creator.
//

import SwiftUI
import AVKit

// MARK: - Media

/// Follows an `AVPlayer` and reports consumption for one playback session.
@MainActor
final class PlaybackReporter {

    /// How much media time must accumulate before we write again. Short enough
    /// that a force-quit loses little, long enough not to chatter.
    private static let heartbeat: Double = 20

    private let play: PracticePlay
    /// Whose play this is, fixed when the player opened. A sign-out mid-listen
    /// must not re-attribute the remaining heartbeats to the next session.
    private let owner: UUID?
    private weak var player: AVPlayer?
    private var observer: Any?
    private var endObserver: (any NSObjectProtocol)?

    private var meter: MediaTimeMeter
    private var reportedAt: Double = 0
    private var didFinish = false

    init(play: PracticePlay) {
        self.play = play
        self.owner = PracticeProgressStore.shared.currentUserID
        self.meter = MediaTimeMeter(durationSeconds: play.durationSeconds,
                                    earlier: PracticeProgressStore.shared.progress(for: play))
    }

    /// Where this practice was left last time, if anywhere. The player seeks
    /// here before starting.
    var resumePosition: Double {
        guard let progress = PracticeProgressStore.shared.progress(for: play),
              progress.isResumable else { return 0 }
        return Double(progress.positionSeconds)
    }

    func attach(to player: AVPlayer) {
        self.player = player
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(CMTimeGetSeconds(time)) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.meter.markReachedEnd()
                self.flush()
            }
        }
    }

    private func tick(_ time: Double) {
        guard time.isFinite else { return }
        meter.observe(time)
        if meter.playedSeconds - reportedAt >= Self.heartbeat { flush() }
    }

    /// Writes what has accumulated so far. Safe to call repeatedly — the row is
    /// upserted on the play's event id, and the DB trigger keeps
    /// `seconds_played` monotonic.
    func flush() {
        guard meter.playedSeconds > 0 || meter.didComplete else { return }
        reportedAt = meter.playedSeconds
        let seconds = Int(meter.playedSeconds.rounded())
        let position = Int(meter.positionSeconds.rounded())
        let completed = meter.didComplete
        Task { [owner] in
            await PracticeProgressStore.shared.record(play,
                                                      owner: owner,
                                                      secondsPlayed: seconds,
                                                      positionSeconds: position,
                                                      completed: completed)
        }
    }

    /// Final write + teardown. Idempotent, because `onDisappear` and a sheet
    /// dismissal can both land.
    func finish() {
        guard !didFinish else { return }
        didFinish = true
        flush()
        if let observer, let player { player.removeTimeObserver(observer) }
        observer = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}

/// The arithmetic `PlaybackReporter` credits a creator by: media time actually
/// played, from the player's periodic observations, and whether that amounts to
/// finishing the session. Kept apart from AVFoundation so it can be tested
/// (`SoulfullTests/MediaTimeMeterTests`).
struct MediaTimeMeter {

    /// Media-time jump beyond which a tick is treated as a seek rather than
    /// playback. The observer fires every second, so anything past this is not
    /// listening.
    static let seekThreshold: Double = 2

    /// How much of a session's length must actually have been played for
    /// reaching its end to count as finishing it.
    ///
    /// Reaching the end used to be enough, so scrubbing a session to its last
    /// seconds finished it — a class on the You tab, a day kept in the streak,
    /// an activity ticked off in a digital retreat. The fifth left over is room
    /// for skipping an intro or a closing silence, not the session.
    static let requiredShare: Double = 0.8

    let durationSeconds: Int?
    /// Media time listened to in this member's earlier, unfinished sittings of
    /// the same session — so one heard across two days still finishes.
    let earlierSeconds: Double
    private(set) var playedSeconds: Double = 0
    private(set) var positionSeconds: Double = 0
    private(set) var didComplete = false
    private var lastMediaTime: Double?

    /// - Parameter earlier: this member's progress on the session before this
    ///   sitting. Unfinished, what was played counts toward finishing. Already
    ///   finished, nothing carries over: hearing it again counts again only if
    ///   it is actually heard again.
    init(durationSeconds: Int?, earlier: PracticeProgress? = nil) {
        self.durationSeconds = durationSeconds
        earlierSeconds = earlier.map { $0.completed ? 0 : Double(max(0, $0.totalSecondsPlayed)) } ?? 0
    }

    /// One periodic reading of the player's media time.
    mutating func observe(_ time: Double) {
        guard time.isFinite else { return }
        defer { lastMediaTime = time }

        if let last = lastMediaTime {
            let delta = time - last
            // Forward, and small enough to be real playback rather than a seek.
            if delta > 0, delta <= Self.seekThreshold {
                playedSeconds += delta
            }
        }
        positionSeconds = time

        // Some encoders leave the last fraction of a second unreachable, so
        // "the end" is a threshold rather than an equality.
        if let durationSeconds, durationSeconds > 0,
           time >= Double(durationSeconds) - Self.seekThreshold {
            reachedEnd(ofLength: Double(durationSeconds))
        }
    }

    /// The item played through to its end — which it also does after a scrub
    /// to its last seconds, so this finishes it only if enough was heard.
    mutating func markReachedEnd() {
        // Without a known length, where the end turned out to be is the length.
        reachedEnd(ofLength: durationSeconds.map(Double.init) ?? positionSeconds)
    }

    /// Finishes the session if enough of it was actually played. Latched:
    /// seeking back afterwards doesn't un-finish it, and falling short now
    /// can still be made good by playing more and reaching the end again.
    private mutating func reachedEnd(ofLength length: Double) {
        guard length > 0 else { return }
        if earlierSeconds + playedSeconds >= Self.requiredShare * length {
            didComplete = true
        }
    }
}

// MARK: - Written practices (journal / movement / recipes)

/// Records time-on-screen for a practice that has no transport to measure.
private struct PracticeActivityModifier: ViewModifier {

    /// Identifies the content. Its `eventID` is NOT used: the caller writes
    /// `.practiceActivity(.journal(prompt))` inside `body`, so a fresh
    /// `PracticePlay` — and a fresh event id — is minted on every re-render.
    /// Journal detail re-renders on every keystroke, so using it would scatter
    /// one sitting across many ledger rows and bill a creator for the sum of
    /// them. `WrittenSitting.eventID` is the stable one.
    let play: PracticePlay
    /// Off when something else is already measuring this content — a written
    /// practice that also carries media reports through `PlaybackReporter`, and
    /// recording dwell as well would pay its creator twice for one sitting.
    let enabled: Bool
    /// Whether the practice counts as done. Evaluated at write time so a view
    /// can answer from its own state — a journal reflection with words in it,
    /// say. When `nil`, dwell alone decides.
    let completedWhen: (() -> Bool)?
    /// A new sitting began on this same screen (see `WrittenSitting`): what
    /// "done in this sitting" is measured from starts again.
    let onNewSitting: (() -> Void)?

    private static let heartbeat: Duration = .seconds(30)

    @Environment(\.scenePhase) private var scenePhase

    /// This visit's sitting: its ledger row, its clock, and what has been
    /// written there. Created once per view identity, which is exactly what
    /// `@State` guarantees.
    @State private var sitting = WrittenSitting()
    /// Whose sitting this is, fixed on appear — see `PlaybackReporter.owner`.
    @State private var owner: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Also fires on coming back from a screen pushed over this one
                // ("Your guide", say). The visit carries on from where it was:
                // restarting the clock here meant a recipe left for its guide's
                // page and returned to could never reach its 45 seconds.
                if sitting.appeared(at: .now, foreground: scenePhase == .active, calendar: .current) {
                    onNewSitting?()
                }
                if owner == nil { owner = PracticeProgressStore.shared.currentUserID }
            }
            .task {
                // Periodic write, so a practice left open and then force-quit
                // still credits what was actually spent on it.
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.heartbeat)
                    guard !Task.isCancelled else { return }
                    write()
                }
            }
            // Bank the sitting and stop the clock: time spent on a screen
            // pushed over this one isn't time on this one.
            .onDisappear {
                sitting.disappeared(at: .now)
                write()
            }
            // `onDisappear` does NOT fire when the app is backgrounded, so
            // without this the clock ran through it: open a prompt, background
            // the phone overnight, come back and tap Back, and the ledger got
            // eight hours of "reading". Stop the clock on the way out and
            // restart it on the way back in — banked, so returning continues
            // the count rather than restarting it (the row's seconds are
            // monotonic server-side, so a restart would silently discard the
            // shorter sitting).
            .onChange(of: scenePhase) { _, phase in
                if sitting.sceneChanged(active: phase == .active, at: .now, calendar: .current) {
                    onNewSitting?()
                }
                if phase != .active { write() }
            }
    }

    private func write() {
        guard enabled,
              let report = sitting.report(at: .now, isComplete: { dwell in
                  completedWhen?() ?? (dwell >= WrittenSitting.dwellForCompletion)
              })
        else { return }
        let entry = PracticePlay(kind: play.kind, contentID: play.contentID,
                                 title: play.title, creator: play.creator,
                                 category: play.category,
                                 durationSeconds: play.durationSeconds,
                                 eventID: sitting.eventID)
        Task { [owner] in
            await PracticeProgressStore.shared.record(entry,
                                                      owner: owner,
                                                      secondsPlayed: report.seconds,
                                                      positionSeconds: report.seconds,
                                                      completed: report.completed)
        }
    }
}

/// One visit's record of a written practice, as the ledger sees it: the play
/// row its heartbeats land on, its `DwellClock`, and what has already been
/// written there. Kept apart from SwiftUI so it can be tested
/// (`SoulfullTests/WrittenSittingTests`).
///
/// **A sitting belongs to the day it began.** Tabs keep their screens, so a
/// prompt left open on one can be come back to the next morning, and writing
/// there landed on yesterday's row: past a day the server had closed it and
/// kept nothing (0029), and inside a day it counted yesterday. Coming back to
/// the screen on a later local day now starts a new sitting — a new row and a
/// fresh clock — and says so, so the screen can reset what it measures "done"
/// from. A sitting that simply runs on past midnight stays one sitting.
struct WrittenSitting {

    /// Long enough to mean the screen was read rather than glanced at.
    static let dwellForCompletion: TimeInterval = 45
    /// Below this nothing is written: a glance is not a sitting.
    static let minimumDwell: TimeInterval = 5

    private(set) var eventID = UUID()
    private(set) var clock = DwellClock()
    /// The local day this sitting's clock first ran on.
    private var day: Date?
    private var reportedSeconds: TimeInterval = 0
    private var reportedComplete = false

    /// The screen is on top. True when this begins a new sitting.
    mutating func appeared(at now: Date, foreground: Bool, calendar: Calendar) -> Bool {
        let wasRunning = clock.isRunning
        clock.appeared(at: now, foreground: foreground)
        return clockStarted(wasRunning: wasRunning, at: now, calendar: calendar)
    }

    /// Another screen was pushed over this one, or it was popped.
    mutating func disappeared(at now: Date) {
        clock.disappeared(at: now)
    }

    /// The scene went to or from the foreground. True when this begins a new
    /// sitting.
    mutating func sceneChanged(active: Bool, at now: Date, calendar: Calendar) -> Bool {
        let wasRunning = clock.isRunning
        clock.sceneChanged(active: active, at: now)
        return clockStarted(wasRunning: wasRunning, at: now, calendar: calendar)
    }

    /// What to write now, or nil when the ledger already has it all.
    ///
    /// More time, or a finish not yet written. Time alone stops growing at the
    /// cap (`DwellClock.maxDwell`), and gating on it meant a reflection first
    /// written after half an hour with the prompt open never counted as done.
    mutating func report(at now: Date,
                         isComplete: (TimeInterval) -> Bool) -> (seconds: Int, completed: Bool)? {
        guard clock.hasStarted else { return nil }
        let dwell = clock.dwell(at: now)
        guard dwell >= Self.minimumDwell else { return nil }
        let completed = isComplete(dwell)
        guard dwell > reportedSeconds || (completed && !reportedComplete) else { return nil }
        reportedSeconds = dwell
        reportedComplete = reportedComplete || completed
        return (Int(dwell.rounded()), completed)
    }

    /// The clock may just have started running again. On a later local day
    /// than this sitting began, that begins a new one.
    private mutating func clockStarted(wasRunning: Bool, at now: Date, calendar: Calendar) -> Bool {
        guard !wasRunning, clock.isRunning else { return false }
        let today = calendar.startOfDay(for: now)
        guard let day else {
            day = today
            return false
        }
        guard day != today else { return false }
        clock.restart(at: now)
        eventID = UUID()
        reportedSeconds = 0
        reportedComplete = false
        self.day = today
        return true
    }
}

/// The arithmetic `.practiceActivity(_:)` credits a written practice by: time
/// its screen was actually in front of the member, over every sitting of one
/// visit. Kept apart from SwiftUI so it can be tested
/// (`SoulfullTests/DwellClockTests`).
///
/// The clock runs only while the screen is both on top (between `appeared`
/// and `disappeared`) and in an active scene. Each stop banks the sitting, so
/// leaving for a pushed screen or the home screen and coming back continues
/// the count. A visit is one view identity: popping the screen ends it.
struct DwellClock {

    /// A visit longer than this is someone who walked away with the screen
    /// open, not someone reading. Wall-clock needs a ceiling of its own: the
    /// lengths the server clamps against are nominal for these libraries (a
    /// journal prompt's 900 seconds, a recipe's cooking time), and a screen
    /// left open would otherwise run up to them every time.
    static let maxDwell: TimeInterval = 30 * 60

    /// Time from sittings that have already ended within this visit.
    private(set) var banked: TimeInterval = 0
    /// When the live sitting began, while the clock is running.
    private var runningSince: Date?
    private var onScreen = false
    private var foreground = false

    /// Whether any sitting has begun — before one has, there is nothing to
    /// write.
    var hasStarted: Bool { runningSince != nil || banked > 0 }

    /// On top, in the foreground, and counting.
    var isRunning: Bool { runningSince != nil }

    /// The screen is on top. Picks up where the visit left off; a second
    /// `appeared` without a `disappeared` between them changes nothing.
    mutating func appeared(at now: Date, foreground: Bool) {
        onScreen = true
        self.foreground = foreground
        settle(at: now)
    }

    /// Another screen was pushed over this one, or it was popped.
    mutating func disappeared(at now: Date) {
        onScreen = false
        settle(at: now)
    }

    /// The scene went to or from the foreground. Coming back to the app
    /// restarts the clock only for a screen that is still on top — one under
    /// a pushed screen stays stopped.
    mutating func sceneChanged(active: Bool, at now: Date) {
        foreground = active
        settle(at: now)
    }

    /// Starts the count again from `now`, as a new visit: nothing banked, and
    /// running only if the screen is on top in the foreground.
    mutating func restart(at now: Date) {
        banked = 0
        runningSince = onScreen && foreground ? now : nil
    }

    /// Foreground time on screen across every sitting of this visit, capped.
    func dwell(at now: Date) -> TimeInterval {
        let live = runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return min(banked + live, Self.maxDwell)
    }

    private mutating func settle(at now: Date) {
        let shouldRun = onScreen && foreground
        if shouldRun {
            if runningSince == nil { runningSince = now }
        } else if let since = runningSince {
            banked += max(0, now.timeIntervalSince(since))
            runningSince = nil
        }
    }
}

extension View {
    /// Records this screen as a practice: how long it was open, and whether it
    /// counts as done. Use on the written libraries; media reports itself
    /// through `PlaybackReporter`.
    func practiceActivity(_ play: PracticePlay,
                          enabled: Bool = true,
                          completedWhen: (() -> Bool)? = nil,
                          onNewSitting: (() -> Void)? = nil) -> some View {
        modifier(PracticeActivityModifier(play: play, enabled: enabled,
                                          completedWhen: completedWhen,
                                          onNewSitting: onNewSitting))
    }
}
