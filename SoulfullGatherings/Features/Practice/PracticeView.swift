//
//  PracticeView.swift
//  Soulfull Gatherings
//
//  The Practice tab landing: a magazine of ways in. One-column feature
//  spreads by default; pinch out (or tap the grid button) and the cards
//  morph into a two-column contact sheet — the LazyVGrid animates the
//  layout change because card identity is stable. Cards are zoom-hero
//  sources into their section.
//

import SwiftUI

struct PracticeView: View {
    let onSelect: (PracticeMenuItem) -> Void
    /// Zoom-hero namespace owned by PracticeRoot.
    var zoomNamespace: Namespace.ID? = nil

    /// True = contact sheet (2-up covers), false = feature spread.
    @State private var sheet = false

    private var columns: [GridItem] {
        sheet
        ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        : [GridItem(.flexible())]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LazyVGrid(columns: columns, spacing: sheet ? 12 : 20) {
                    ForEach(Array(PracticeMenuItem.allCases.enumerated()), id: \.element) { idx, item in
                        card(item, folio: idx + 1)
                    }
                }
                Color.clear.frame(height: 120)
            }
            .padding(.top, 28)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .pinchBrowsable(zoomedOut: $sheet)
        .background {
            PhotoBackdrop(imageName: "home-bg", blur: 3, darken: 0.76)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WELLNESS LIBRARY")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.muted)
                Text("Practices")
                    .font(Theme.headline(38))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
                Text(sheet
                     ? "The whole library, side by side."
                     : "Choose a way in. Sessions for every state — listen or watch, anytime.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .padding(.top, 4)
                    .animation(nil, value: sheet)
            }
            Spacer()
            CircleIconButton(systemName: sheet ? "rectangle.portrait" : "square.grid.2x2", size: 40) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { sheet.toggle() }
            }
            .accessibilityLabel(sheet ? "Feature view" : "Grid view")
        }
        .padding(.bottom, 6)
    }

    // MARK: - Card (feature spread ⇄ contact-sheet cover)

    private func card(_ item: PracticeMenuItem, folio: Int) -> some View {
        let height: CGFloat = sheet ? 168 : 210
        return PressableCard(action: { onSelect(item) }) {
            ZStack(alignment: .bottomLeading) {
                Image(item.imageName)
                    .resizable().scaledToFill()
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(1.15)
                    .scrollParallax(strength: sheet ? 0 : 18)
                    .frame(height: height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.35), .black.opacity(0.72)],
                    startPoint: .top, endPoint: .bottom
                )

                // Folio number
                VStack {
                    HStack {
                        Spacer()
                        Text(String(format: "%02d", folio))
                            .font(Theme.body(11, weight: .medium))
                            .tracking(1.5)
                            .foregroundStyle(Color.white.opacity(0.8))
                            .padding(12)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: sheet ? 5 : 8) {
                    HStack(spacing: 8) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: sheet ? 11 : 13, weight: .semibold))
                        Text(item.title.uppercased())
                            .font(Theme.eyebrow(sheet ? 9 : 11))
                            .tracking(sheet ? 1.4 : 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(.white)

                    if !sheet {
                        Text(item.blurb)
                            .font(Theme.body(13))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)

                        HStack(spacing: 6) {
                            Text("Explore")
                                .font(Theme.body(12, weight: .semibold))
                                .tracking(0.4)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.top, 2)
                        .transition(.opacity)
                    }
                }
                .padding(sheet ? 12 : 18)
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .soulGlassCard(radius: Theme.cardRadius)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            // Clip the hit-test region to the card bounds — `scaledToFill`
            // overflow would otherwise steal taps from neighbors.
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .modifier(PracticeZoomSource(id: item.rawValue, namespace: zoomNamespace))
        .scrollTransition(.interactive(timingCurve: .easeOut), axis: .vertical) { view, phase in
            let entering = max(phase.value, 0)
            return view
                .opacity(1 - entering * 0.55)
                .scaleEffect(1 - entering * 0.05)
                .offset(y: entering * 22)
        }
    }
}

/// Registers a zoom-hero source when the owning stack provided a namespace.
struct PracticeZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

#Preview {
    NavigationStack {
        PracticeView(onSelect: { _ in })
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
