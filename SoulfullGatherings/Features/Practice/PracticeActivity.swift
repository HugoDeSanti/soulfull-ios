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
//    • `.practiceActivity(_:)` for the written libraries (journal, exercises,
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
    /// Media-time jump beyond which a tick is treated as a seek rather than
    /// playback. The observer fires every second, so anything past this is not
    /// listening.
    private static let seekThreshold: Double = 2

    private let play: PracticePlay
    private weak var player: AVPlayer?
    private var observer: Any?
    private var endObserver: (any NSObjectProtocol)?

    private var lastMediaTime: Double?
    private var playedSeconds: Double = 0
    private var positionSeconds: Double = 0
    private var reportedAt: Double = 0
    private var didComplete = false
    private var didFinish = false

    init(play: PracticePlay) {
        self.play = play
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
                self.didComplete = true
                self.flush()
            }
        }
    }

    private func tick(_ time: Double) {
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
        if let duration = play.durationSeconds, duration > 0,
           time >= Double(duration) - Self.seekThreshold {
            didComplete = true
        }

        if playedSeconds - reportedAt >= Self.heartbeat { flush() }
    }

    /// Writes what has accumulated so far. Safe to call repeatedly — the row is
    /// upserted on the play's event id, and the DB trigger keeps
    /// `seconds_played` monotonic.
    func flush() {
        guard playedSeconds > 0 || didComplete else { return }
        reportedAt = playedSeconds
        let seconds = Int(playedSeconds.rounded())
        let position = Int(positionSeconds.rounded())
        let completed = didComplete
        Task { await PracticeProgressStore.shared.record(play,
                                                         secondsPlayed: seconds,
                                                         positionSeconds: position,
                                                         completed: completed) }
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

// MARK: - Written practices (journal / exercises / recipes)

/// Records time-on-screen for a practice that has no transport to measure.
private struct PracticeActivityModifier: ViewModifier {

    /// Identifies the content. Its `eventID` is NOT used: the caller writes
    /// `.practiceActivity(.journal(prompt))` inside `body`, so a fresh
    /// `PracticePlay` — and a fresh event id — is minted on every re-render.
    /// Journal detail re-renders on every keystroke, so using it would scatter
    /// one sitting across many ledger rows and bill a creator for the sum of
    /// them. `eventID` below is the stable one.
    let play: PracticePlay
    /// Off when something else is already measuring this content — a massage
    /// with media reports through `PlaybackReporter`, and recording dwell as
    /// well would pay its creator twice for one sitting.
    let enabled: Bool
    /// Whether the practice counts as done. Evaluated at write time so a view
    /// can answer from its own state — a journal reflection with words in it,
    /// say. When `nil`, dwell alone decides.
    let completedWhen: (() -> Bool)?

    /// Long enough to mean the screen was read rather than glanced at.
    private static let dwellForCompletion: TimeInterval = 45
    private static let heartbeat: Duration = .seconds(30)

    @State private var openedAt: Date?
    @State private var reported: TimeInterval = 0
    /// One id for this screen's whole visit, so every heartbeat upserts the
    /// same ledger row instead of adding another. Created once per view
    /// identity, which is exactly what `@State` guarantees.
    @State private var eventID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { openedAt = .now }
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
    }

    private func write() {
        guard enabled, let openedAt else { return }
        let dwell = Date.now.timeIntervalSince(openedAt)
        guard dwell >= 5, dwell > reported else { return }
        reported = dwell
        let completed = completedWhen?() ?? (dwell >= Self.dwellForCompletion)
        let seconds = Int(dwell.rounded())
        let sitting = PracticePlay(kind: play.kind, contentID: play.contentID,
                                   title: play.title, creator: play.creator,
                                   category: play.category,
                                   durationSeconds: play.durationSeconds,
                                   eventID: eventID)
        Task { await PracticeProgressStore.shared.record(sitting,
                                                         secondsPlayed: seconds,
                                                         positionSeconds: seconds,
                                                         completed: completed) }
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
