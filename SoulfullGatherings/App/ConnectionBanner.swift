//
//  ConnectionBanner.swift
//  Soulfull Gatherings
//
//  Surfaces a failed session so it isn't silent.
//
//  Before this, a launch with no network left `AuthManager.state == .failed`
//  and said nothing: the app carried on with fallback content, and the user
//  only found out when something that needed a session threw a raw error
//  string at them. The banner states the problem once, quietly, and offers the
//  one useful action.
//

import SwiftUI

struct ConnectionBanner: View {
    @Environment(AuthManager.self) private var auth
    @State private var isRetrying = false

    var body: some View {
        if auth.needsRetry {
            HStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.honey)

                VStack(alignment: .leading, spacing: 2) {
                    Text("You're offline")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("Showing saved content. Some things won't work yet.")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    Haptics.tap()
                    Task {
                        isRetrying = true
                        await auth.retry()
                        isRetrying = false
                    }
                } label: {
                    Group {
                        if isRetrying {
                            ProgressView().controlSize(.small).tint(Theme.ink)
                        } else {
                            Text("Retry")
                                .font(Theme.body(12, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .frame(minWidth: 44)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .soulGlassCapsule()
                }
                .buttonStyle(.soulPressableQuiet)
                .disabled(isRetrying)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .soulGlassCard(radius: 16)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You're offline. Showing saved content.")
            .accessibilityHint("Double tap Retry to reconnect")
        }
    }
}
