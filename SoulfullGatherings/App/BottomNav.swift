//
//  BottomNav.swift
//  Soulfull Gatherings
//
//  A flat bar docked to the bottom edge: five evenly spaced items, a thin
//  glyph over a small label, cream when selected and muted when not. It does
//  not move — no sliding lens, no bounce, no squish — so the only thing that
//  changes on a tap is the colour. The You item is the member's own face
//  (their photo, or their initial on their tone); a guest, who has no face
//  yet, sees the plain person glyph.
//

import SwiftUI

struct BottomNav: View {
    @Binding var current: MainTab

    var body: some View {
        HStack(spacing: 0) {
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
                    .fixedSize()
            }
            .foregroundStyle(active ? Theme.ink : Theme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(StaticNavButtonStyle())
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

/// The member's face, ringed in cream while the You tab is selected.
private struct YouNavIcon: View {
    let active: Bool
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if auth.hasAccount {
            AvatarView(avatarUrl: settings.avatarUrl,
                       name: settings.userName,
                       seed: auth.userID?.uuidString ?? "",
                       size: 22)
                .padding(2)
                .overlay {
                    Circle().strokeBorder(active ? Theme.ink : .clear, lineWidth: 1.2)
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
