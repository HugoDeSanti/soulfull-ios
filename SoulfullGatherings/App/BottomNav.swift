//
//  BottomNav.swift
//  Soulfull Gatherings
//
//  A flat bar docked to the bottom edge: six evenly spaced items, a thin
//  glyph over a small label, ink when selected and muted when not. It does
//  not move — no sliding lens, no bounce, no squish — so the only thing that
//  changes on a tap is the colour. The You item is the member's own face
//  (their photo, or their initial on their tone); a guest, who has no face
//  yet, sees the plain person glyph.
//

import SwiftUI

struct BottomNav: View {
    @Binding var current: MainTab

    /// How far the bar reaches above the bottom safe area (8 + 46 + 2 below).
    /// For a screen that pins something to its foot under the bar — most tab
    /// roots scroll and just end on a tall spacer instead.
    static let height: CGFloat = 56

    var body: some View {
        NavBarLayout {
            ForEach(MainTab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background {
            Theme.bgDeep.opacity(0.94)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.line).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        // Static on purpose: nothing inherited from a surrounding transaction
        // animates the bar either.
        .transaction { $0.animation = nil }
    }

    private func item(_ tab: MainTab) -> some View {
        let active = current == tab
        return Button {
            guard tab != current else { return }
            Haptics.select()
            current = tab
        } label: {
            VStack(spacing: 5) {
                icon(tab, active: active)
                    .frame(height: 26)
                Text(tab.label)
                    .font(Theme.body(10, weight: .medium))
                    .tracking(0.3)
                    .lineLimit(1)
                    // Only ever used when the bar is too narrow for every label
                    // at full size — see `NavBarLayout`.
                    .minimumScaleFactor(0.7)
                    // The bar's height is fixed, so the labels stop growing at
                    // the largest standard size; past it, a long press shows
                    // the large content viewer, as the system tab bar does.
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
            .foregroundStyle(active ? Theme.ink : Theme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(StaticNavButtonStyle())
        .accessibilityShowsLargeContentViewer {
            Label(tab.label, systemImage: tab.systemImage)
        }
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private func icon(_ tab: MainTab, active: Bool) -> some View {
        if tab == .you {
            YouNavIcon(active: active)
        } else {
            Image(systemName: tab.systemImage)
                .font(.system(size: 19, weight: .light))
        }
    }
}

/// Lays the items out edge to edge, each as wide as its own label plus an equal
/// share of whatever is left over.
///
/// Equal slots stopped working at six: "Digital Retreats" is ~77pt at 10pt
/// Geist, a sixth of a 402pt phone is ~64pt, and the label ran into
/// "Gatherings" beside it. Sizing slots to their content keeps the gaps
/// between labels even instead, and the slots still tile the whole bar, so
/// every point of it answers a tap.
private struct NavBarLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: proposal.width ?? sizes.map(\.width).reduce(0, +),
                      height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let natural = widths.reduce(0, +)
        let spare = (bounds.width - natural) / CGFloat(subviews.count)
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            // Too narrow for every label at full size (a small phone at a large
            // text size): share the width out in proportion instead, and let
            // the labels scale down to it.
            let slot = spare >= 0 ? width + spare : width * bounds.width / natural
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: slot, height: bounds.height))
            x += slot
        }
    }
}

/// The member's face, ringed in ink while the You tab is selected. A face is
/// the one thing the app keeps round.
private struct YouNavIcon: View {
    let active: Bool
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if auth.hasAccount {
            AvatarView(avatarUrl: settings.avatarUrl,
                       name: settings.name.full,
                       seed: auth.userID?.uuidString ?? "",
                       size: 22)
                .padding(2)
                .overlay {
                    Circle().strokeBorder(active ? Theme.ink : .clear, lineWidth: 1)
                }
                .opacity(active ? 1 : 0.75)
        } else {
            Image(systemName: MainTab.you.systemImage)
                .font(.system(size: 20, weight: .light))
        }
    }
}

/// No scale, no dim, no spring — a tab bar that holds still under the finger.
private struct StaticNavButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

#Preview {
    ZStack {
        PhotoBackdrop(imageName: "home-bg", blur: 3, darken: 0.5)
        VStack { Spacer(); BottomNav(current: .constant(.home)) }
    }
    .environment(AuthManager(settings: AppSettings()))
    .environment(AppSettings())
    .preferredColorScheme(.dark)
}
