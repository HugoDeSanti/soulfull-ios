//
//  PracticePlayerView.swift
//  Soulfull Gatherings
//
//  Resolves a session's media URL and plays it. Audio gets the full
//  now-playing room: an aurora graded from the artwork, a breathing ring
//  around a square-cut cover, a hairline scrubber with haptic ends, ±15s,
//  and a square play/pause. Video keeps AVKit's transport inside branded
//  chrome.
//
//  URL resolution: absolute http(s) paths play directly; bucket-relative
//  paths are signed via `SupabaseService.signedMediaURL`.
//
//  Plays in a `.playback` audio session (`PlaybackAudioSession`), so the
//  ringer switch doesn't silence it and an audio session carries on with the
//  phone locked, with its card and controls on the lock screen
//  (`AudioTransport`).
//

import SwiftUI
import AVKit
import MediaPlayer

/// Why a session couldn't be opened — see `Error.isOffline`.
private enum PlayerLoadFailure {
    case offline
    case failed

    init(offline: Bool) { self = offline ? .offline : .failed }

    var title: String {
        switch self {
        case .offline: "No internet connection"
        case .failed:  "Couldn't load this session"
        }
    }

    var detail: String {
        switch self {
        case .offline: "You'll need to be online to play this session. Reconnect and try again."
        case .failed:  "Something went wrong at our end. Please try again in a moment."
        }
    }

    var systemImage: String {
        switch self {
        case .offline: "wifi.slash"
        case .failed:  "exclamationmark.circle"
        }
    }
}

struct PracticePlayerView: View {
    let media: MediaItem
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var transport: AudioTransport?
    @State private var loadFailure: PlayerLoadFailure?
    /// Bumped by "Try again": the load is `.task(id:)` on it, so a bump
    /// re-runs it.
    @State private var attempt = 0
    @State private var tones: (top: Color, mid: Color, base: Color)?
    /// Counts what is actually listened to and heartbeats it to the ledger the
    /// creator payouts are drawn from. Built in `resolveAndPlay` once the
    /// media has resolved (the `@State` initialiser can't see `media`) and one
    /// per presentation, so each listen is its own row. See
    /// `PracticeActivity.swift`.
    @State private var reporter: PlaybackReporter?
    /// Notices the session breaking after it started — see
    /// `PlaybackFailureWatch`.
    @State private var failureWatch: PlaybackFailureWatch?
    /// Where a session that broke mid-listen had got to, so "Try again"
    /// carries on from there rather than from the last resume point.
    @State private var resumeAfterFailure: Double?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let player {
                if media.mediaKind == .video {
                    videoStage(player)
                } else {
                    audioStage
                }
            } else if let loadFailure {
                errorView(loadFailure)
            } else {
                AuroraBackground(speed: 0.9)
                    .ignoresSafeArea()
                    .overlay(ProgressView().tint(Theme.ink))
            }

            // Close
            VStack {
                HStack {
                    Spacer()
                    GlyphButton(systemName: "xmark") {
                        Haptics.tap()
                        dismiss()
                    }
                    .accessibilityLabel("Close player")
                }
                Spacer()
            }
            // The 44pt target's glyph sits ~13pt inside it; this lands the ×
            // on the page margin.
            .padding(.horizontal, Theme.gutter - 13)
            .padding(.top, 14)
        }
        .preferredColorScheme(.dark)
        .presentationCornerRadius(0)
        .task(id: attempt) { await resolveAndPlay() }
        .onAppear { tones = ArtworkTones.extract(from: media.imageUrl) }
        .onDisappear { tearDown() }
    }

    /// Everything the player started, stopped. The reporter's final write
    /// reads only its own meter, so the item can go after it — and must go
    /// before the audio session is handed back: deactivating a session that
    /// still has a player item attached fails as busy, and whatever the member
    /// was listening to before wouldn't be told it can resume.
    private func tearDown() {
        failureWatch?.stop()
        player?.pause()
        transport?.stop()
        reporter?.finish()
        guard let player else { return }
        player.replaceCurrentItem(with: nil)
        PlaybackAudioSession.deactivate()
    }

    // MARK: - Audio stage

    private var audioStage: some View {
        ZStack {
            // The room the session happens in: the artwork's own tones
            // drifting at breath pace. No grain — the room is still.
            Group {
                if let tones {
                    AuroraBackground(tones: tones, speed: 0.9)
                } else {
                    AuroraBackground(speed: 0.9)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // The breath circle around a square-cut cover. The ring is the
                // one guide that moves: it widens and fades at breath pace.
                ZStack {
                    Circle()
                        .strokeBorder(Theme.ink.opacity(0.22), lineWidth: Theme.hairline)
                        .frame(width: 312, height: 312)
                        .breathing(scale: 0.94...1.06, opacity: 0.25...0.6)

                    CatalogImage(media.imageUrl) { $0.resizable().scaledToFill() }
                        .frame(width: 220, height: 220)
                        .clipped()
                        .overlay(
                            Rectangle()
                                .strokeBorder(Theme.ink.opacity(0.18), lineWidth: Theme.hairline)
                        )
                }
                .padding(.bottom, 48)

                VStack(spacing: 10) {
                    Text("NOW PLAYING · \(media.durationLabel)".uppercased())
                        .font(Theme.eyebrow(10))
                        .tracking(2.5)
                        .foregroundStyle(Theme.inkSoft)
                    Text(media.title)
                        .font(Theme.headline(28, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .kerning(-0.6)
                    // The guide, as a chip that opens their profile — the
                    // sheet closes first so it is pushed on the stack below.
                    GuideCredit(instructorID: media.instructorID,
                                beforeOpen: { dismiss() }, from: media.title) {
                        Text("with \(media.lead)")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.top, 2)
                    if let reminder = media.category?.safetyReminder {
                        Text(reminder)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                            .accessibilityIdentifier("player-safety")
                    }
                }
                .padding(.horizontal, Theme.gutter + 8)

                Spacer()

                if let transport {
                    VStack(spacing: 26) {
                        SoulScrubber(transport: transport)
                        transportButtons(transport)
                    }
                    .padding(.bottom, 54)
                }
            }
        }
    }

    private func transportButtons(_ transport: AudioTransport) -> some View {
        HStack(spacing: 44) {
            skipButton(icon: "gobackward.15", by: -AudioTransport.skipInterval, transport: transport)

            // A square drawn in a hairline, the glyph crossfading between
            // play and pause — no disc, no morph.
            Button {
                Haptics.bump()
                transport.togglePlay()
            } label: {
                Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .regular))
                    .contentTransition(.opacity)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 72, height: 72)
                    .overlay(Rectangle().strokeBorder(Theme.ink.opacity(0.7), lineWidth: Theme.hairline))
                    .contentShape(Rectangle())
            }
            .buttonStyle(SoulPressableStyle(hapticOnPress: false))
            .accessibilityLabel(transport.isPlaying ? "Pause" : "Play")

            skipButton(icon: "goforward.15", by: AudioTransport.skipInterval, transport: transport)
        }
    }

    private func skipButton(icon: String, by seconds: Double, transport: AudioTransport) -> some View {
        Button {
            transport.skip(seconds)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.ink)
                .frame(width: 52, height: 52)
                // Gotcha #5: a framed glyph answers only where it draws, so
                // the 52pt square around it was dead.
                .contentShape(Rectangle())
        }
        .buttonStyle(.soulPressable)
        .accessibilityLabel(seconds < 0 ? "Back 15 seconds" : "Forward 15 seconds")
    }

    // MARK: - Video stage (AVKit transport, branded chrome)

    private func videoStage(_ player: AVPlayer) -> some View {
        ZStack {
            VideoPlayer(player: player)
                .ignoresSafeArea()

            // Title chrome over a soft top gradient; AVKit owns the rest.
            VStack {
                LinearGradient(colors: [.black.opacity(0.55), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("with \(media.lead)".uppercased())
                                .font(Theme.eyebrow(9))
                                .tracking(2)
                                .foregroundStyle(Theme.inkSoft)
                            Text(media.title)
                                .font(Theme.headline(20, weight: .light))
                                .foregroundStyle(Theme.ink)
                                .kerning(-0.3)
                            if let reminder = media.category?.safetyReminder {
                                Text(reminder)
                                    .font(Theme.body(11))
                                    .foregroundStyle(Theme.inkSoft)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                        .padding(.bottom, 8)
                    }
                    .allowsHitTesting(false)
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    /// The session couldn't be opened: why — offline, or our end — and a way
    /// to try again without closing the player.
    private func errorView(_ failure: PlayerLoadFailure) -> some View {
        VStack(spacing: 12) {
            Image(systemName: failure.systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.muted)
            Text(failure.title)
                .font(Theme.headline(20, weight: .light))
                .foregroundStyle(Theme.ink)
            Text(failure.detail)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                loadFailure = nil
                attempt += 1
            } label: {
                Text("Try again")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .soulGlassCard()
            }
            .buttonStyle(.soulPressableQuiet)
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Resolve URL → AVPlayer

    private func resolveAndPlay() async {
        guard player == nil else { return }
        // History has to be in hand before the resume point is read, and this
        // view is presented as a sheet from wherever media lives — so don't
        // assume a caller already loaded it. No-ops when it's current.
        await PracticeProgressStore.shared.refresh()
        do {
            let url: URL
            if media.storagePath.hasPrefix("http"), let direct = URL(string: media.storagePath) {
                // Externally-hosted / sample media (or a public Storage URL).
                url = direct
            } else {
                // Private bucket object → time-limited signed URL.
                url = try await SupabaseService.shared.signedMediaURL(path: media.storagePath)
            }
            // Closed while the URL was being signed. `onDisappear` has already
            // been and gone, so carrying on would start a session nobody can
            // see or stop.
            guard !Task.isCancelled else { return }
            let reporter = PlaybackReporter(play: .media(media))
            let avPlayer = AVPlayer(url: url)

            // Pick up where they left off. Only offered for a practice that was
            // genuinely under way — see `PracticeProgress.isResumable` — or
            // where this one broke, on "Try again".
            let resumeAt = resumeAfterFailure ?? reporter.resumePosition
            resumeAfterFailure = nil
            if resumeAt > 0 {
                await avPlayer.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600),
                                    toleranceBefore: .zero, toleranceAfter: .zero)
                guard !Task.isCancelled else { return }
            }

            PlaybackAudioSession.activate(for: media.mediaKind)
            if media.mediaKind == .audio {
                let t = AudioTransport(player: avPlayer, duration: Double(media.durationSeconds),
                                       title: media.title, guide: media.lead)
                t.currentTime = resumeAt
                t.start()
                transport = t
            }
            self.reporter = reporter
            reporter.attach(to: avPlayer)
            if let item = avPlayer.currentItem {
                failureWatch = PlaybackFailureWatch(item: item) { error in playbackBroke(error) }
            }
            player = avPlayer
            avPlayer.play()
        } catch where error.isCancellation {
            // Closed mid-load; there's nobody left to tell.
        } catch {
            Log.media.error("Couldn't resolve media: \(error.localizedDescription)")
            loadFailure = PlayerLoadFailure(offline: error.isOffline)
        }
    }

    /// The session stopped being playable mid-listen. Bank what was heard, let
    /// go of the broken player and say why; "Try again" signs a fresh URL and
    /// carries on from the same moment.
    private func playbackBroke(_ error: (any Error)?) {
        guard let player else { return }
        Log.media.error("Playback failed: \(error?.localizedDescription ?? "no error given")")
        let position = CMTimeGetSeconds(player.currentTime())
        resumeAfterFailure = position.isFinite && position > 0 ? position : nil
        tearDown()
        self.player = nil
        transport = nil
        reporter = nil
        failureWatch = nil
        loadFailure = PlayerLoadFailure(offline: error?.isOffline ?? false)
    }
}

// MARK: - Playback failure

/// Notices a session that stops being playable after it started: the signed
/// URL ran out during a long pause (it lasts an hour), or the stream lost its
/// connection. The player used to sit on a Play button that did nothing, with
/// no word of why.
@MainActor
final class PlaybackFailureWatch {
    private let item: AVPlayerItem
    private let onFailure: @MainActor ((any Error)?) -> Void
    private var statusObservation: NSKeyValueObservation?
    private var failedObserver: (any NSObjectProtocol)?
    private var fired = false

    init(item: AVPlayerItem, onFailure: @escaping @MainActor ((any Error)?) -> Void) {
        self.item = item
        self.onFailure = onFailure
        // KVO may call back on any thread: hop to the main actor and read the
        // status there.
        statusObservation = item.observe(\.status, options: [.new]) { @Sendable [weak self] _, _ in
            Task { @MainActor in self?.check() }
        }
        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? any Error
            MainActor.assumeIsolated { self?.fail(error) }
        }
    }

    func stop() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let failedObserver { NotificationCenter.default.removeObserver(failedObserver) }
        failedObserver = nil
    }

    private func check() {
        if item.status == .failed { fail(item.error) }
    }

    /// Once: the status and the notification can both report one failure.
    private func fail(_ error: (any Error)?) {
        guard !fired else { return }
        fired = true
        stop()
        onFailure(error ?? item.error)
    }
}

// MARK: - Audio session

/// The audio session a practice plays in.
///
/// `.playback`, because the session is the point of the screen: under the
/// default `.soloAmbient` the ringer switch silenced it and locking the phone
/// stopped it (the latter also needs `UIBackgroundModes: audio`, in
/// `project.yml`). `.spokenAudio` for audio, so a navigation prompt pauses a
/// guided voice rather than talking over it; `.moviePlayback` for video.
/// Handed back with `.notifyOthersOnDeactivation` when the player closes, so
/// music or a podcast it interrupted can resume.
///
/// Failures are logged, never fatal: AVPlayer still plays in the default
/// session, just less well.
@MainActor
enum PlaybackAudioSession {

    static func activate(for kind: MediaKind) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: kind == .video ? .moviePlayback : .spokenAudio)
            try session.setActive(true)
        } catch {
            Log.media.error("Couldn't start the audio session: \(error.localizedDescription)")
        }
    }

    static func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Log.media.error("Couldn't end the audio session: \(error.localizedDescription)")
        }
    }
}

// MARK: - Custom scrubber (hairline track, a tick for the playhead, haptic ends)

private struct SoulScrubber: View {
    @Bindable var transport: AudioTransport
    @State private var dragging = false
    /// The rail (0 or 1) the thumb is held against mid-drag, if any — so the
    /// detent clicks once on arrival rather than on every drag event spent
    /// pressed against the end.
    @State private var rail: Double?

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let width = geo.size.width
                let fraction = transport.duration > 0
                    ? min(1, max(0, transport.currentTime / transport.duration))
                    : 0

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.ink.opacity(0.18))
                        .frame(height: dragging ? 3 : 1)

                    Rectangle()
                        .fill(Theme.ink)
                        .frame(width: max(0, width * fraction), height: dragging ? 3 : 1)

                    // The playhead: an upright tick, taller under the finger.
                    Rectangle()
                        .fill(Theme.ink)
                        .frame(width: 2, height: dragging ? 22 : 14)
                        .offset(x: width * fraction - 1)
                }
                .frame(height: 26)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !dragging {
                                dragging = true
                                transport.isScrubbing = true
                                Haptics.prepare()
                            }
                            let f = min(1, max(0, value.location.x / max(width, 1)))
                            transport.currentTime = f * transport.duration
                            // Detent at the rails, once on arrival.
                            let atRail: Double? = (f == 0 || f == 1) ? f : nil
                            if let atRail, atRail != rail { Haptics.select() }
                            rail = atRail
                        }
                        .onEnded { _ in
                            transport.seek(to: transport.currentTime)
                            transport.isScrubbing = false
                            dragging = false
                            rail = nil
                            Haptics.select()
                        }
                )
                .animation(dragging ? Theme.Motion.press : Theme.Motion.release, value: dragging)
            }
            .frame(height: 26)

            HStack {
                Text(Self.time(transport.currentTime))
                Spacer()
                Text("-" + Self.time(max(0, transport.duration - transport.currentTime)))
            }
            .font(Theme.body(11))
            .monospacedDigit()
            .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, Theme.gutter + 6)
        // One element for VoiceOver, which can't perform the drag: swiping up
        // or down moves 15 seconds, as the buttons beside it do.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Self.time(transport.currentTime)) of \(Self.time(transport.duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: transport.skip(AudioTransport.skipInterval)
            case .decrement: transport.skip(-AudioTransport.skipInterval)
            @unknown default: break
            }
        }
    }

    /// `mm:ss` from a seconds value, defensively clamping non-finite input.
    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Drives the audio stage: mirrors `AVPlayer` time into observable state for the
/// scrubber, and turns scrub/skip gestures back into seeks. The periodic time
/// observer fires on the main queue, so `MainActor.assumeIsolated` lets it touch
/// this `@MainActor` state without an extra hop.
///
/// It also owns the session's place on the lock screen and in Control Center:
/// the Now Playing card (title, guide, length, position, rate) and the remote
/// play / pause / ±15s / scrub commands, which go through the same methods as
/// the controls on screen. None of it touches `PlaybackReporter`, which counts
/// media time from the player itself: a skip from the lock screen is a seek
/// like any other, and banks nothing.
@Observable @MainActor
final class AudioTransport {
    /// The skip on screen, and the lock screen's.
    static let skipInterval: Double = 15

    var currentTime: Double = 0
    var duration: Double
    var isPlaying = true
    /// While the user drags the scrubber, suppress observer-driven updates so
    /// the thumb doesn't fight the finger.
    var isScrubbing = false

    private let player: AVPlayer
    /// What the Now Playing card says.
    private let title: String
    private let guide: String
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var remoteTargets: [RemoteTarget] = []
    /// Between `start` and `stop`. A remote command that arrives after the
    /// player has closed must not put its card back on the lock screen.
    @ObservationIgnored private var isLive = false

    private struct RemoteTarget {
        let command: MPRemoteCommand
        let token: Any
    }

    init(player: AVPlayer, duration: Double, title: String, guide: String) {
        self.player = player
        self.duration = max(duration, 1)
        self.title = title
        self.guide = guide
    }

    func start() {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        isLive = true
        installRemoteCommands()
        publishNowPlaying()
    }

    func stop() {
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
        isLive = false
        for target in remoteTargets {
            target.command.removeTarget(target.token)
            target.command.isEnabled = false
        }
        remoteTargets = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Five times a second. Each property is written only when it changes:
    /// `@Observable` tells every reader of a property it was SET, equal or
    /// not, so writing `isPlaying` and `duration` on every tick re-ran the
    /// player's whole body five times a second for a whole session, when only
    /// the scrubber (the one reader of `currentTime`) moves.
    private func tick(_ time: CMTime) {
        let wasPlaying = isPlaying
        let knownDuration = duration
        // Prefer the asset's true duration once it's known; fall back to metadata.
        if let itemDuration = player.currentItem?.duration, itemDuration.isNumeric {
            let secs = CMTimeGetSeconds(itemDuration)
            if secs.isFinite, secs > 0, secs != duration { duration = secs }
        }
        if !isScrubbing {
            let seconds = CMTimeGetSeconds(time)
            if seconds != currentTime { currentTime = seconds }
        }
        let playing = player.timeControlStatus != .paused
        if playing != isPlaying { isPlaying = playing }
        // The lock screen runs its own clock from the last position and rate
        // it was given, so it needs telling only when one of those changes —
        // a pause from a phone call, say — not five times a second.
        if isPlaying != wasPlaying || duration != knownDuration { publishNowPlaying() }
    }

    func play() {
        guard !isPlaying else { return }
        // Replay from the top if we're parked at the end.
        if currentTime >= duration - 0.25 { seek(to: 0) }
        player.play()
        isPlaying = true
        publishNowPlaying()
    }

    func pause() {
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
        publishNowPlaying()
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    func skip(_ seconds: Double) {
        seek(to: min(max(currentTime + seconds, 0), duration))
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        publishNowPlaying()
    }

    // MARK: Lock screen and Control Center

    private func publishNowPlaying() {
        guard isLive else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: guide,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let interval = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.preferredIntervals = interval
        center.skipForwardCommand.preferredIntervals = interval

        onRemote(center.playCommand) { $0.play() }
        onRemote(center.pauseCommand) { $0.pause() }
        onRemote(center.togglePlayPauseCommand) { $0.togglePlay() }
        onRemote(center.skipBackwardCommand) { $0.skip(-AudioTransport.skipInterval) }
        onRemote(center.skipForwardCommand) { $0.skip(AudioTransport.skipInterval) }

        // Dragging the lock screen's scrubber.
        let scrub = center.changePlaybackPositionCommand
        scrub.isEnabled = true
        let token = scrub.addTarget { @Sendable [weak self] event in
            guard let self,
                  let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
            else { return .commandFailed }
            Task { @MainActor in
                if self.isLive { self.seek(to: position) }
            }
            return .success
        }
        remoteTargets.append(RemoteTarget(command: scrub, token: token))
    }

    /// Wires one remote command to this transport. The handler hops to the
    /// main actor rather than assuming it is already there: MediaPlayer makes
    /// no promise about which thread a command arrives on.
    private func onRemote(_ command: MPRemoteCommand,
                          perform: @escaping @Sendable @MainActor (AudioTransport) -> Void) {
        command.isEnabled = true
        let token = command.addTarget { @Sendable [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            Task { @MainActor in
                if self.isLive { perform(self) }
            }
            return .success
        }
        remoteTargets.append(RemoteTarget(command: command, token: token))
    }
}

#Preview {
    // Shape-only: `storagePath` is empty, so the player renders its load-error
    // state. Point this at a real Storage path to preview playback.
    PracticePlayerView(media: MediaItem(
        id: 1, title: "Grounding Body Scan", lead: "Dr. Anya Iyer",
        imageUrl: "retreat-images/sedona-2026-06.jpg", mediaKind: .audio,
        storagePath: "", durationSeconds: 720
    ))
}
