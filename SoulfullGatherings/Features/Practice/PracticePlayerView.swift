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
        .onDisappear { player?.pause() }
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

            if let player {
                PlayPauseButton(player: player)
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
            player = avPlayer
            avPlayer.play()
        } catch {
            print("[PracticePlayerView] couldn't resolve media: \(error)")
            loadError = "Couldn't load this session. Please try again."
        }
    }
}

// MARK: - Minimal play/pause control for the audio stage

private struct PlayPauseButton: View {
    let player: AVPlayer
    @State private var isPlaying = true

    var body: some View {
        Button {
            Haptics.bump()
            if isPlaying { player.pause() } else { player.play() }
            isPlaying.toggle()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 72, height: 72)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.2), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PracticePlayerView(media: PracticeSession.mock(for: .somatic).first!.media)
}
