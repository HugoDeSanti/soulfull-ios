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
//  It owns its own spacing and animation, and takes no room at all while the
//  session is healthy, so its host can inset content by exactly its height.
//

import SwiftUI

struct ConnectionBanner: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        // A container, not a bare `if`: the animation has to sit outside the
        // conditional to animate it in and out. Empty, it measures zero.
        VStack(spacing: 0) {
            // `needsRetry` stays true for the whole of a retry (`isRetrying`
            // only swaps the button for a spinner), so the banner no longer
            // slides away the moment Retry is tapped.
            if auth.needsRetry {
                banner
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: auth.needsRetry)
    }

    /// Offline and "our end" call for different things: reconnecting, or
    /// waiting a moment. The banner said "You're offline" for both.
    private var isOffline: Bool { auth.connectionFailure == .offline }

    private var title: String {
        isOffline ? "You're offline" : "Couldn't reach Soulfull right now"
    }

    // NOT "showing saved content" — there is none. The retreat fallback was
    // removed (see `RetreatsLoadFailure`), so offline means the catalog is
    // genuinely unavailable, and each surface says so in its own empty state.
    private var message: String {
        isOffline
            ? "Reconnect to load retreats and practices."
            : "Something went wrong at our end. Try again in a moment."
    }

    private var banner: some View {
        HStack(spacing: 12) {
            Image(systemName: isOffline ? "wifi.exclamationmark" : "exclamationmark.icloud")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.honey)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                Haptics.tap()
                Task { await auth.retry() }
            } label: {
                Group {
                    if auth.isRetrying {
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
                // Glass adds no tappable fill on iOS 26 (gotcha #5).
                .contentShape(Capsule())
            }
            .buttonStyle(.soulPressableQuiet)
            .disabled(auth.isRetrying)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .soulGlassCard(radius: 16)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityValue(auth.isRetrying ? "Reconnecting" : "")
        .accessibilityHint(auth.isRetrying ? "" : "Double tap Retry to reconnect")
    }
}

extension View {
    /// Puts the connection banner in this screen's top safe area, so it moves
    /// the screen down rather than covering its top bar — the Back link of
    /// every pushed page, used to sit right under it. Applied to each tab's
    /// root and to every screen pushed in a tab's stack: an inset around the
    /// tab pager, or around a NavigationStack, never reaches the screens hosted
    /// inside them (checked with the banner forced on).
    func connectionBannerInset() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { ConnectionBanner() }
    }
}
