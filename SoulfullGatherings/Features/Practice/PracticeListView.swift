//
//  PracticeListView.swift
//  Soulfull Gatherings
//
//  Lists every audio / video session for one practice category. Tapping a row
//  opens `PracticePlayerView`, which resolves the Storage URL and plays.
//

import SwiftUI

struct PracticeListView: View {
    let category: PracticeCategory

    @State private var vm = PracticeViewModel()
    @State private var nowPlaying: PracticeSession?

    var body: some View {
        PracticeListScaffold(
            title: category.title,
            blurb: category.blurb,
            systemImage: category.systemImage,
            backdrop: category.imageName
        ) {
            if vm.isLoading {
                ProgressView()
                    .tint(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else if let error = vm.loadError {
                errorState(error)
            } else if vm.sessions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.sessions) { session in
                        PressableCard(action: { nowPlaying = session }) {
                            sessionRow(session)
                        }
                        .scrollTransition(.interactive(timingCurve: .easeOut), axis: .vertical) { view, phase in
                            let entering = max(phase.value, 0)
                            return view
                                .opacity(1 - entering * 0.5)
                                .offset(y: entering * 18)
                        }
                    }
                }
            }
        }
        .task(id: category) { await vm.load(category: category) }
        .sheet(item: $nowPlaying) { session in
            PracticePlayerView(media: session.media)
        }
    }

    // MARK: - Session row

    private func sessionRow(_ session: PracticeSession) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Image(session.imageUrl)
                    .resizable().scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Image(systemName: session.mediaKind == .video ? "play.fill" : "waveform")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.glassBorder, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(Theme.headline(17))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .lineLimit(1)
                Text("with \(session.lead)")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(session.mediaKind.label, systemImage: session.mediaKind.systemImage)
                        .labelStyle(.titleAndIcon)
                    Text("·")
                    Text(session.durationLabel)
                }
                .font(Theme.eyebrow(10))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .soulGlassCard(radius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: category.systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.muted)
            Text("Nothing here yet.")
                .font(Theme.headline(20))
                .foregroundStyle(Theme.ink)
            Text("New \(category.title.lowercased()) sessions are on the way.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    /// The fetch itself failed — say so and offer a way back, rather than
    /// implying the library is empty.
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.muted)
            Text("Couldn't load")
                .font(Theme.headline(20))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                Task { await vm.load(category: category) }
            } label: {
                Text("Try again")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .soulGlassCapsule()
            }
            .buttonStyle(.soulPressableQuiet)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

#Preview {
    NavigationStack {
        PracticeListView(category: .somatic)
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
