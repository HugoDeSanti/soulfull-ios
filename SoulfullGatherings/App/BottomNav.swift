//
//  BottomNav.swift
//  Soulfull Gatherings
//
//  One continuous liquid-glass capsule. A cream "lens" slides behind the
//  active tab with a springy overshoot; the active icon fills, bounces, and
//  reveals its label. Inactive items are quiet glyphs on glass.
//

import SwiftUI

struct BottomNav: View {
    @Binding var current: MainTab
    @Namespace private var lens

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
        .padding(6)
        .soulGlassCapsule(interactive: true, stroke: Theme.glassBorderHigh)
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: current)
    }

    private func item(_ tab: MainTab) -> some View {
        let active = current == tab
        return Button {
            guard tab != current else { return }
            Haptics.tap()
            current = tab
        } label: {
            HStack(spacing: 7) {
                Image(systemName: active ? tab.activeSystemImage : tab.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .symbolEffect(.bounce.down.byLayer, value: active)
                    .frame(width: 22)

                if active {
                    Text(tab.label)
                        .font(Theme.body(13, weight: .medium))
                        .tracking(0.3)
                        .fixedSize()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)).combined(with: .scale(scale: 0.8, anchor: .leading)),
                            removal: .opacity
                        ))
                }
            }
            .foregroundStyle(active ? Color.black : Color.white.opacity(0.85))
            .padding(.horizontal, active ? 18 : 13)
            .frame(height: 46)
            .background {
                if active {
                    Capsule()
                        .fill(Theme.ink)
                        .matchedGeometryEffect(id: "lens", in: lens)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(SoulPressableStyle(scale: 0.93, hapticOnPress: false, dim: false))
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

#Preview {
    ZStack {
        PhotoBackdrop(imageName: "home-bg", blur: 3, darken: 0.5)
        VStack { Spacer(); BottomNav(current: .constant(.home)) }
    }
    .preferredColorScheme(.dark)
}
