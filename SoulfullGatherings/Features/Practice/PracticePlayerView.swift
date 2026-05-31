//
//  PracticePlayerView.swift
//  Soulfull Gatherings
//
//  Resolves a session's media URL and plays it. Absolute http(s) paths play
//  directly; bucket-relative paths are turned into a time-limited signed URL
//  via `SupabaseService.signedMediaURL`. Video uses AVKit's `VideoPlayer`;
//  audio gets a minimal branded transport over an `AVPlayer`.
//

import SwiftUI
import AVKit

struct PracticePlayerView: View {
    let media: MediaItem
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var transport: AudioTransport?
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let player {
                if media.mediaKind == .video {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    audioStage
                }
            } else if let loadError {
                errorView(loadError)
            } else {
                ProgressView()
                    .tint(Theme.ink)
            }

            VStack {
                HStack {
                    Spacer()
                    CircleIconButton(systemName: "xmark", size: 38) {
                        Haptics.tap()
                        dismiss()
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
        .task { await resolveAndPlay() }
        .onDisappear {
            player?.pause()
            transport?.stop()
        }
    }

    // MARK: - Audio stage (cover art + title; AVPlayer drives playback)

    private var audioStage: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(media.imageUrl)
                .resizable().scaledToFill()
                .frame(width: 240, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.glassBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)

            VStack(spacing: 6) {
                Text(media.title)
                    .font(Theme.headline(26))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .kerning(-0.3)
                Text("with \(media.lead) · \(media.durationLabel)")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 28)

            if let transport {
                AudioControls(transport: transport)
            }
            Spacer()
            Spacer()
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
            if media.mediaKind == .audio {
                let t = AudioTransport(player: avPlayer, duration: Double(media.durationSeconds))
                t.start()
                transport = t
            }
            player = avPlayer
            avPlayer.play()
        } catch {
            print("[PracticePlayerView] couldn't resolve media: \(error)")
            loadError = "Couldn't load this session. Please try again."
        }
    }
}

// MARK: - Audio transport (scrubber + skip + play/pause)

private struct AudioControls: View {
    @Bindable var transport: AudioTransport

    var body: some View {
        VStack(spacing: 20) {
            scrubber
            buttons
        }
    }

    // Draggable progress bar with elapsed / remaining labels.
    private var scrubber: some View {
        VStack(spacing: 8) {
            Slider(
                value: $transport.currentTime,
                in: 0...max(transport.duration, 1),
                onEditingChanged: { editing in
                    transport.isScrubbing = editing
                    if editing {
                        Haptics.prepare()
                    } else {
                        transport.seek(to: transport.currentTime)
                        Haptics.select()
                    }
                }
            )
            .tint(Theme.ink)

            HStack {
                Text(Self.time(transport.currentTime))
                Spacer()
                Text("-" + Self.time(max(0, transport.duration - transport.currentTime)))
            }
            .font(Theme.body(11))
            .monospacedDigit()
            .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 28)
    }

    private var buttons: some View {
        HStack(spacing: 40) {
            skip(icon: "gobackward.15", by: -15)
            playPause
            skip(icon: "goforward.15", by: 15)
        }
    }

    private var playPause: some View {
        Button {
            Haptics.bump()
            transport.togglePlay()
        } label: {
            Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 72, height: 72)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.2), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func skip(icon: String, by seconds: Double) -> some View {
        Button {
            Haptics.tap()
            transport.skip(seconds)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
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
private final class AudioTransport {
    var currentTime: Double = 0
    var duration: Double
    var isPlaying = true
    /// While the user drags the slider, suppress observer-driven updates so the
    /// thumb doesn't fight the finger.
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
    PracticePlayerView(media: PracticeSession.mock(for: .somatic).first!.media)
}
