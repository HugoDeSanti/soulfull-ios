//
//  PracticePlayerView.swift
//  Soulfull Gatherings
//
//  Resolves a session's media URL and plays it. Audio gets the full
//  now-playing room: an aurora graded from the artwork, breathing halo and
//  cover, a custom scrubber with haptic ends, ±15s, and a morphing
//  play/pause. Video keeps AVKit's transport inside branded chrome.
//
//  URL resolution: absolute http(s) paths play directly; bucket-relative
//  paths are signed via `SupabaseService.signedMediaURL`.
//

import SwiftUI
import AVKit

struct PracticePlayerView: View {
    let media: MediaItem
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var transport: AudioTransport?
    @State private var loadError: String?
    @State private var tones: (top: Color, mid: Color, base: Color)?
    /// Counts what is actually listened to and heartbeats it to the ledger the
    /// creator payouts are drawn from. Built in `resolveAndPlay` (the `@State`
    /// initialiser can't see `media`) and one per presentation, so each listen
    /// is its own row. See `PracticeActivity.swift`.
    @State private var reporter: PlaybackReporter?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let player {
                if media.mediaKind == .video {
                    videoStage(player)
                } else {
                    audioStage
                }
            } else if let loadError {
                errorView(loadError)
            } else {
                AuroraBackground(speed: 1.2)
                    .ignoresSafeArea()
                    .overlay(ProgressView().tint(Theme.ink))
            }

            // Close
            VStack {
                HStack {
                    Spacer()
                    CircleIconButton(systemName: "xmark", size: 38) {
                        Haptics.tap()
                        dismiss()
                    }
                    .accessibilityLabel("Close player")
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .preferredColorScheme(.dark)
        .task { await resolveAndPlay() }
        .onAppear { tones = ArtworkTones.extract(from: media.imageUrl) }
        .onDisappear {
            player?.pause()
            transport?.stop()
            reporter?.finish()
        }
    }

    // MARK: - Audio stage

    private var audioStage: some View {
        ZStack {
            AuroraBackground(
                toneA: tones?.base ?? Color(red: 0.10, green: 0.12, blue: 0.05),
                toneB: tones?.mid ?? Color(red: 0.24, green: 0.27, blue: 0.10),
                toneC: tones?.top ?? Color(red: 0.36, green: 0.31, blue: 0.13),
                speed: 0.9
            )
            .filmGrain(intensity: 0.05)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Breathing halo + artwork
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        .frame(width: 312, height: 312)
                        .breathing(scale: 0.92...1.1, opacity: 0.25...0.6, period: 6)
                    Circle()
                        .fill(
                            RadialGradient(colors: [Color.white.opacity(0.10), .clear],
                                           center: .center, startRadius: 60, endRadius: 220)
                        )
                        .frame(width: 430, height: 430)
                        .breathing(scale: 0.9...1.08, opacity: 0.5...1.0, period: 6)

                    CatalogImage(media.imageUrl) { $0.resizable().scaledToFill() }
                        .frame(width: 248, height: 248)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
                        .breathing(scale: 0.985...1.015, opacity: 1.0...1.0, period: 6)
                }
                .padding(.bottom, 36)

                VStack(spacing: 8) {
                    Text("NOW PLAYING · \(media.durationLabel)".uppercased())
                        .font(Theme.eyebrow(10))
                        .tracking(2.5)
                        .foregroundStyle(Color.white.opacity(0.6))
                    Text(media.title)
                        .font(Theme.headline(28))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .kerning(-0.4)
                    Text("with \(media.lead)")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 28)

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
            skipButton(icon: "gobackward.15", by: -15, transport: transport)

            Button {
                Haptics.bump()
                transport.togglePlay()
            } label: {
                Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                    .foregroundStyle(.black)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            }
            .buttonStyle(SoulPressableStyle(scale: 0.92, hapticOnPress: false, dim: false))
            .accessibilityLabel(transport.isPlaying ? "Pause" : "Play")

            skipButton(icon: "goforward.15", by: 15, transport: transport)
        }
    }

    private func skipButton(icon: String, by seconds: Double, transport: AudioTransport) -> some View {
        Button {
            transport.skip(seconds)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.soulPressableChip)
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
                                .foregroundStyle(Color.white.opacity(0.7))
                            Text(media.title)
                                .font(Theme.headline(20))
                                .foregroundStyle(.white)
                                .kerning(-0.3)
                        }
                        .padding(.horizontal, 22)
                        .padding(.bottom, 8)
                    }
                    .allowsHitTesting(false)
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.muted)
            Text(message)
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
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
        let reporter = PlaybackReporter(play: .media(media))
        self.reporter = reporter
        do {
            let url: URL
            if media.storagePath.hasPrefix("http"), let direct = URL(string: media.storagePath) {
                // Externally-hosted / sample media (or a public Storage URL).
                url = direct
            } else {
                // Private bucket object → time-limited signed URL.
                url = try await SupabaseService.shared.signedMediaURL(path: media.storagePath)
            }
            let avPlayer = AVPlayer(url: url)

            // Pick up where they left off. Only offered for a practice that was
            // genuinely under way — see `PracticeProgress.isResumable`.
            let resumeAt = reporter.resumePosition
            if resumeAt > 0 {
                await avPlayer.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600),
                                    toleranceBefore: .zero, toleranceAfter: .zero)
            }

            if media.mediaKind == .audio {
                let t = AudioTransport(player: avPlayer, duration: Double(media.durationSeconds))
                t.currentTime = resumeAt
                t.start()
                transport = t
            }
            reporter.attach(to: avPlayer)
            player = avPlayer
            avPlayer.play()
        } catch {
            Log.media.error("Couldn't resolve media: \(error.localizedDescription)")
            loadError = "Couldn't load this session. Please try again."
        }
    }
}

// MARK: - Custom scrubber (capsule track, draggable, haptic ends)

private struct SoulScrubber: View {
    @Bindable var transport: AudioTransport
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let width = geo.size.width
                let fraction = transport.duration > 0
                    ? min(1, max(0, transport.currentTime / transport.duration))
                    : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: dragging ? 10 : 5)

                    Capsule()
                        .fill(Theme.ink)
                        .frame(width: max(0, width * fraction), height: dragging ? 10 : 5)

                    Circle()
                        .fill(Color.white)
                        .frame(width: dragging ? 18 : 12, height: dragging ? 18 : 12)
                        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                        .offset(x: width * fraction - (dragging ? 9 : 6))
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
                            // Detent at the rails.
                            if f == 0 || f == 1 { Haptics.select() }
                        }
                        .onEnded { _ in
                            transport.seek(to: transport.currentTime)
                            transport.isScrubbing = false
                            dragging = false
                            Haptics.select()
                        }
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging)
            }
            .frame(height: 26)

            HStack {
                Text(Self.time(transport.currentTime))
                Spacer()
                Text("-" + Self.time(max(0, transport.duration - transport.currentTime)))
            }
            .font(Theme.body(11))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(.horizontal, 30)
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
@Observable @MainActor
final class AudioTransport {
    var currentTime: Double = 0
    var duration: Double
    var isPlaying = true
    /// While the user drags the scrubber, suppress observer-driven updates so
    /// the thumb doesn't fight the finger.
    var isScrubbing = false

    private let player: AVPlayer
    private var observer: Any?

    init(player: AVPlayer, duration: Double) {
        self.player = player
        self.duration = max(duration, 1)
    }

    func start() {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
    }

    func stop() {
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
    }

    private func tick(_ time: CMTime) {
        // Prefer the asset's true duration once it's known; fall back to metadata.
        if let itemDuration = player.currentItem?.duration, itemDuration.isNumeric {
            let secs = CMTimeGetSeconds(itemDuration)
            if secs.isFinite, secs > 0 { duration = secs }
        }
        if !isScrubbing { currentTime = CMTimeGetSeconds(time) }
        isPlaying = player.timeControlStatus != .paused
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // Replay from the top if we're parked at the end.
            if currentTime >= duration - 0.25 {
                seek(to: 0)
                currentTime = 0
            }
            player.play()
            isPlaying = true
        }
    }

    func skip(_ seconds: Double) {
        let target = min(max(currentTime + seconds, 0), duration)
        currentTime = target
        seek(to: target)
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
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
