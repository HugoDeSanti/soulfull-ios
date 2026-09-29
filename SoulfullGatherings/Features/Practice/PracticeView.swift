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

    /// Which media tracks have sessions behind them — or `.unknown` while the
    /// check is in flight or if it failed (offline). Seeding
    /// `practice_sessions` lights the tracks up with no client release.
    @State private var availability: SupabaseService.CategoryAvailability = .unknown

    /// Categories known to have content. Empty while `.unknown`.
    private var availableCategories: Set<PracticeCategory> {
        if case .known(let set) = availability { return set }
        return []
    }

    /// A media card is live once its category is known to have sessions — or
    /// while we simply don't know, because being offline is not the same as a
    /// track being empty. An optimistic card that turns out to have nothing
    /// behind it lands on `PracticeListView`, which has a real error state and
    /// a retry; a pessimistic one tells a user on a train that content they
    /// paid for doesn't exist.
    /// Bespoke sections (journal, movement, recipes) are always live.
    private func isAvailable(_ item: PracticeMenuItem) -> Bool {
        guard let category = item.mediaCategory else { return true }
        switch availability {
        case .known(let set): return set.contains(category)
        case .unknown:        return true
        }
    }

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
        .task {
            availability = await SupabaseService.shared.availablePracticeCategories()
        }
    }

    // MARK: - Header

    /// Only *known* emptiness drops the "listen or watch" promise. While the
    /// check is in flight or failed, the cards are open, so the copy must not
    /// contradict them by saying sessions are still on the way.
    private var headerBlurb: String {
        if case .known(let set) = availability, set.isEmpty {
            return "Choose a way in. Prompts to sit with, movement and food — guided sessions on the way."
        }
        return "Choose a way in. Sessions for every state — listen or watch, anytime."
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WELLNESS LIBRARY")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)
                Text("Practices")
                    .font(Theme.headline(38))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
                // Don't promise audio and video while the media tracks are
                // still "Coming soon"; the line corrects itself once
                // `practice_sessions` is seeded.
                Text(sheet ? "The whole library, side by side." : headerBlurb)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(4)
                    .padding(.top, 4)
                    .animation(nil, value: sheet)
            }
            // Floats on a barely-blurred photo — see View.onPhoto().
            .onPhoto()
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
        let live = isAvailable(item)
        return PressableCard(action: { if live { onSelect(item) } }) {
            ZStack(alignment: .bottomLeading) {
                // No image parallax here: visualEffect offsets escape
                // ancestor clips, so clipped cards must keep imagery static.
                Color.clear
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Image(item.imageName)
                            .resizable().scaledToFill()
                    }
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.35), .black.opacity(0.72)],
                    startPoint: .top, endPoint: .bottom
                )

                // Folio number, and — in both layouts, since the contact sheet
                // hides the blurb — a badge when the track has no content yet.
                VStack {
                    HStack(spacing: 8) {
                        if !live {
                            Text("SOON")
                                .font(Theme.eyebrow(9))
                                .tracking(1.4)
                                .foregroundStyle(Color.white.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.black.opacity(0.45)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        }
                        Spacer()
                        Text(String(format: "%02d", folio))
                            .font(Theme.body(11, weight: .medium))
                            .tracking(1.5)
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    .padding(12)
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
                            if live {
                                Text("Explore")
                                    .font(Theme.body(12, weight: .semibold))
                                    .tracking(0.4)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                            } else {
                                Text("Coming soon")
                                    .font(Theme.body(12, weight: .semibold))
                                    .tracking(0.4)
                            }
                        }
                        .foregroundStyle(live ? .white : Color.white.opacity(0.6))
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
            // Quietly recede rather than grey out — the card is still a
            // legible piece of the library, just not open yet.
            .opacity(live ? 1 : 0.62)
        }
        .disabled(!live)
        .accessibilityLabel(live ? item.title : "\(item.title), coming soon")
        .accessibilityHint(live ? "Opens \(item.title)" : "This track has no sessions yet")
        // Only a card that can actually push registers a zoom-hero source.
        .modifier(PracticeZoomSource(id: item.rawValue, namespace: live ? zoomNamespace : nil))
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
