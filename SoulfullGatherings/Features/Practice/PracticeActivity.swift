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
//      nothing, and a paused player accrues nothing.
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
        self.meter = MediaTimeMeter(durationSeconds: play.durationSeconds)
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
                self.meter.markCompleted()
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
/// played, from the player's periodic observations. Kept apart from AVFoundation
/// so it can be tested (`SoulfullTests/MediaTimeMeterTests`).
struct MediaTimeMeter {

    /// Media-time jump beyond which a tick is treated as a seek rather than
    /// playback. The observer fires every second, so anything past this is not
    /// listening.
    static let seekThreshold: Double = 2

    let durationSeconds: Int?
    private(set) var playedSeconds: Double = 0
    private(set) var positionSeconds: Double = 0
    private(set) var didComplete = false
    private var lastMediaTime: Double?

    init(durationSeconds: Int?) {
        self.durationSeconds = durationSeconds
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
        // "finished" is a threshold rather than an equality.
        if let durationSeconds, durationSeconds > 0,
           time >= Double(durationSeconds) - Self.seekThreshold {
            didComplete = true
        }
    }

    /// The item played through to its end.
    mutating func markCompleted() {
        didComplete = true
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
    /// them. `eventID` below is the stable one.
    let play: PracticePlay
    /// Off when something else is already measuring this content — a written
    /// practice that also carries media reports through `PlaybackReporter`, and
    /// recording dwell as well would pay its creator twice for one sitting.
    let enabled: Bool
    /// Whether the practice counts as done. Evaluated at write time so a view
    /// can answer from its own state — a journal reflection with words in it,
    /// say. When `nil`, dwell alone decides.
    let completedWhen: (() -> Bool)?

    /// Long enough to mean the screen was read rather than glanced at.
    private static let dwellForCompletion: TimeInterval = 45
    private static let heartbeat: Duration = .seconds(30)
    /// A reading session longer than this is someone who walked away with the
    /// screen open, not someone reading. Wall-clock needs a ceiling because
    /// most of these practices have no length to clamp against server-side:
    /// `PracticePlay.journal` carries no `durationSeconds` at all, so the DB
    /// trigger's `least(seconds_played, duration_seconds)` is skipped and
    /// nothing bounded the number.
    private static let maxDwell: TimeInterval = 30 * 60

    @Environment(\.scenePhase) private var scenePhase

    @State private var openedAt: Date?
    /// Foreground seconds from sittings that have already ended (the screen was
    /// backgrounded and returned to) within this same visit.
    @State private var banked: TimeInterval = 0
    @State private var reported: TimeInterval = 0
    /// One id for this screen's whole visit, so every heartbeat upserts the
    /// same ledger row instead of adding another. Created once per view
    /// identity, which is exactly what `@State` guarantees.
    @State private var eventID = UUID()
    /// Whose sitting this is, fixed on appear — see `PlaybackReporter.owner`.
    @State private var owner: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear {
                openedAt = .now
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
            .onDisappear { write() }
            // `onDisappear` does NOT fire when the app is backgrounded, so
            // without this the clock ran through it: open a prompt, background
            // the phone overnight, come back and tap Back, and the ledger got
            // eight hours of "reading". Stop the clock on the way out and
            // restart it on the way back in.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    if openedAt == nil { openedAt = .now }
                } else {
                    write()
                    // Bank this sitting before stopping the clock, so returning
                    // to the screen continues the count rather than restarting
                    // it (the row's seconds are monotonic server-side, so a
                    // restart would silently discard the shorter sitting).
                    if let openedAt { banked += Date.now.timeIntervalSince(openedAt) }
                    openedAt = nil
                }
            }
    }

    /// Foreground time on this screen across every sitting of this visit,
    /// capped. `banked` covers sittings already ended; `openedAt` the live one.
    private var dwell: TimeInterval {
        let live = openedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        return min(banked + live, Self.maxDwell)
    }

    private func write() {
        guard enabled, openedAt != nil || banked > 0 else { return }
        let dwell = self.dwell
        guard dwell >= 5, dwell > reported else { return }
        reported = dwell
        let completed = completedWhen?() ?? (dwell >= Self.dwellForCompletion)
        let seconds = Int(dwell.rounded())
        let sitting = PracticePlay(kind: play.kind, contentID: play.contentID,
                                   title: play.title, creator: play.creator,
                                   category: play.category,
                                   durationSeconds: play.durationSeconds,
                                   eventID: eventID)
        Task { [owner] in
            await PracticeProgressStore.shared.record(sitting,
                                                      owner: owner,
                                                      secondsPlayed: seconds,
                                                      positionSeconds: seconds,
                                                      completed: completed)
        }
    }
}

extension View {
    /// Records this screen as a practice: how long it was open, and whether it
    /// counts as done. Use on the written libraries; media reports itself
    /// through `PlaybackReporter`.
    func practiceActivity(_ play: PracticePlay,
                          enabled: Bool = true,
                          completedWhen: (() -> Bool)? = nil) -> some View {
        modifier(PracticeActivityModifier(play: play, enabled: enabled, completedWhen: completedWhen))
    }
}
