//
//  BottomNav.swift
//  Soulfull Gatherings
//
//  Floating glass tab bar — four circular icons centered above the home
//  indicator. Active item is solid white, inactive are translucent glass.
//

import SwiftUI

struct BottomNav: View {
    @Binding var current: MainTab

    var body: some View {
        HStack(spacing: 12) {
            ForEach(MainTab.allCases, id: \.self) { t in
                let active = current == t
                Button {
                    if t != current {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            current = t
                        }
                    }
                } label: {
                    Image(systemName: t.systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(active ? Color.black : Color.white.opacity(0.92))
                        .frame(width: active ? 54 : 44, height: active ? 54 : 44)
                        .background(
                            ZStack {
                                if active {
                                    Circle().fill(Color.white)
                                } else {
                                    Circle().fill(.ultraThinMaterial)
                                    Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                }
                            }
                        )
                        .shadow(color: .black.opacity(active ? 0.25 : 0.18),
                                radius: active ? 12 : 6, y: active ? 6 : 3)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: active)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.label)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

#Preview {
    ZStack {
        Theme.bg.ignoresSafeArea()
        VStack { Spacer(); BottomNav(current: .constant(.home)) }
    }
}
