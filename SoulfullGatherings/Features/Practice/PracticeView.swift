//
//  PracticeView.swift
//  Soulfull Gatherings
//
//  The Practice tab landing screen: a scrolling menu of practice tracks
//  (Somatic Therapy, Breathwork, Meditation). Tapping a track pushes
//  `PracticeListView` for that category via the tab's NavigationStack.
//

import SwiftUI

struct PracticeView: View {
    let onSelect: (PracticeMenuItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                ForEach(PracticeMenuItem.allCases) { item in
                    categoryCard(item)
                        .onTapGesture {
                            Haptics.tap()
                            onSelect(item)
                        }
                }
                Color.clear.frame(height: 120)
            }
            .padding(.top, 28)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background {
            PhotoBackdrop(imageName: "home-bg", blur: 3, darken: 0.76)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WELLNESS LIBRARY")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.muted)
            Text("Practices")
                .font(Theme.headline(38))
                .foregroundStyle(Theme.ink)
                .kerning(-0.3)
            Text("Choose a way in. Sessions for every state — listen or watch, anytime.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .padding(.top, 4)
        }
        .padding(.bottom, 6)
    }

    // MARK: - Category card

    private func categoryCard(_ item: PracticeMenuItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(item.imageName)
                .resizable().scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.72)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.title.uppercased())
                        .font(Theme.eyebrow(11))
                        .tracking(2)
                }
                .foregroundStyle(.white)

                Text(item.blurb)
                    .font(Theme.body(13))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text("Explore")
                        .font(Theme.body(12, weight: .semibold))
                        .tracking(0.4)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.top, 2)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        // Clip the hit-test region to the card bounds. `.clipped()`/`.clipShape()`
        // only clip visually; without this the `scaledToFill` image's tap area
        // overflows into the neighboring view above, shifting every card's
        // destination by one (header → first section, first card → second, …).
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        PracticeView(onSelect: { _ in })
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
