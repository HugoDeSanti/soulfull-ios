//
//  MassageView.swift
//  Soulfull Gatherings
//
//  Personal Massages section: guided self-massage. The detail screen plays the
//  guided audio/video (reusing PracticePlayerView) and lists the technique.
//  Mock-driven until a `massages` table is seeded; media resolves the same way
//  as practice sessions (signed Storage URL or direct http).
//

import SwiftUI

struct MassageListView: View {
    let onOpen: (Massage) -> Void
    private let massages = Massage.all

    var body: some View {
        PracticeListScaffold(
            title: PracticeMenuItem.massages.title,
            blurb: PracticeMenuItem.massages.blurb,
            systemImage: PracticeMenuItem.massages.systemImage,
            backdrop: PracticeMenuItem.massages.imageName
        ) {
            VStack(spacing: 10) {
                ForEach(massages) { massage in
                    PressableCard(action: { onOpen(massage) }) {
                        massageRow(massage)
                    }
                    .listReveal()
                }
            }
        }
    }

    private func massageRow(_ massage: Massage) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Image(massage.imageUrl)
                    .resizable().scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Image(systemName: massage.mediaKind == .video ? "play.fill" : "waveform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(massage.title)
                    .font(Theme.headline(17))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .lineLimit(1)
                Text("with \(massage.lead)")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(massage.mediaKind.label, systemImage: massage.mediaKind.systemImage)
                    Text("·")
                    Text(massage.durationLabel)
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
}

// MARK: - Detail

struct MassageDetailView: View {
    let massage: Massage
    @State private var isPlaying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PracticeBackBar(label: "Massages")

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: massage.mediaKind.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(massage.mediaKind.label) · \(massage.durationLabel)".uppercased())
                            .font(Theme.eyebrow(11))
                            .tracking(2)
                    }
                    .foregroundStyle(Theme.inkSoft)

                    Text(massage.title)
                        .font(Theme.headline(32))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("with \(massage.lead)")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.inkOnPhoto)
                    Text(massage.blurb)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.inkOnPhoto)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                // Header block over the photo backdrop.
                .onPhoto()

                // Only offered when real media exists for this technique. The
                // written steps below are the substance either way.
                if massage.media != nil {
                    Button {
                        Haptics.bump()
                        isPlaying = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.system(size: 14, weight: .semibold))
                            Text("Play guided session")
                                .font(Theme.body(15, weight: .medium))
                                .tracking(0.4)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(.white))
                    }
                    .buttonStyle(SoulPressableStyle(scale: 0.97, hapticOnPress: false, dim: false))
                }

                Text("THE TECHNIQUE")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 4)
                    .onPhoto()

                VStack(spacing: 14) {
                    ForEach(Array(massage.steps.enumerated()), id: \.offset) { index, step in
                        NumberedStepRow(index: index + 1, title: step)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))

                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background {
            PhotoBackdrop(imageName: massage.imageUrl, blur: 24, darken: 0.8)
        }
        .sheet(isPresented: $isPlaying) {
            if let media = massage.media {
                PracticePlayerView(media: media)
            }
        }
    }
}

#Preview {
    NavigationStack {
        MassageDetailView(massage: Massage.all[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
