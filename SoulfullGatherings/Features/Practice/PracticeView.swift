//
//  PracticeView.swift
//  Soulfull Gatherings
//
//  The Practice tab landing: a magazine of ways in. One-column feature
//  spreads by default; pinch out (or tap the grid button) and the cards
//  morph into a two-column contact sheet — the LazyVGrid animates the
//  layout change because card identity is stable.
//

import SwiftUI

struct PracticeView: View {
    let onSelect: (PracticeMenuItem) -> Void

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
            VStack(alignment: .leading, spacing: 36) {
                header
                LazyVGrid(columns: columns, spacing: sheet ? 12 : 28) {
                    ForEach(Array(PracticeMenuItem.allCases.enumerated()), id: \.element) { idx, item in
                        card(item, folio: idx + 1)
                    }
                }
                Color.clear.frame(height: 120)
            }
            .padding(.top, 36)
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .statusBarFade()
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
            VStack(alignment: .leading, spacing: 8) {
                Text("WELLNESS LIBRARY")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)
                Text("Practices")
                    .font(Theme.headline(38, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.8)
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
            GlyphButton(systemName: sheet ? "rectangle.portrait" : "square.grid.2x2") {
                withAnimation(Theme.Motion.settle) { sheet.toggle() }
            }
            .padding(.trailing, -12)
            .accessibilityLabel(sheet ? "Feature view" : "Grid view")
        }
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
                                .foregroundStyle(Theme.ink.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Rectangle().fill(.black.opacity(0.45)))
                                .overlay(Rectangle().strokeBorder(Theme.ink.opacity(0.25), lineWidth: Theme.hairline))
                        }
                        Spacer()
                        Text(String(format: "%02d", folio))
                            .font(Theme.body(11, weight: .medium))
                            .tracking(1.5)
                            .foregroundStyle(Theme.ink.opacity(0.8))
                    }
                    .padding(14)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: sheet ? 5 : 8) {
                    HStack(spacing: 8) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: sheet ? 11 : 13, weight: .regular))
                        Text(item.title.uppercased())
                            .font(Theme.eyebrow(sheet ? 9 : 11))
                            .tracking(sheet ? 1.4 : 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Theme.ink)

                    if !sheet {
                        Text(item.blurb)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.inkOnPhoto)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)

                        HStack(spacing: 6) {
                            if live {
                                Text("Explore")
                                    .font(Theme.body(12, weight: .medium))
                                    .tracking(0.4)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .regular))
                            } else {
                                Text("Coming soon")
                                    .font(Theme.body(12, weight: .medium))
                                    .tracking(0.4)
                            }
                        }
                        .foregroundStyle(live ? Theme.ink : Theme.ink.opacity(0.6))
                        .padding(.top, 2)
                        .transition(.opacity)
                    }
                }
                .padding(sheet ? 14 : 20)
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .soulGlassCard()
            .clipped()
            // Clip the hit-test region to the card bounds — `scaledToFill`
            // overflow would otherwise steal taps from neighbors.
            .contentShape(Rectangle())
            // Quietly recede rather than grey out — the card is still a
            // legible piece of the library, just not open yet.
            .opacity(live ? 1 : 0.62)
        }
        .disabled(!live)
        .accessibilityLabel(live ? item.title : "\(item.title), coming soon")
        .accessibilityHint(live ? "Opens \(item.title)" : "This track has no sessions yet")
        // Light only: a card fades up from half-light as it enters; nothing
        // travels or grows.
        .scrollTransition(.interactive(timingCurve: .easeOut), axis: .vertical) { view, phase in
            view.opacity(1 - max(phase.value, 0) * 0.55)
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
