//
//  Pressable.swift
//  Soulfull Gatherings
//
//  Touch. Every tappable surface in the app goes through one of these
//  styles so the response is the same everywhere: on touch-down the surface
//  dims and a soft haptic lands; on release it comes back slowly. Nothing
//  moves — no squish, no spring — a press is a change of light.
//

import SwiftUI

// MARK: - Pressable button style

struct SoulPressableStyle: ButtonStyle {
    /// Haptic fired on touch-down. Actions should not double-fire `tap`.
    var hapticOnPress: Bool = true
    var dim: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(dim && configuration.isPressed ? 0.55 : 1)
            .animation(configuration.isPressed ? Theme.Motion.press : Theme.Motion.release,
                       value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    Haptics.prepare()
                    if hapticOnPress { Haptics.tap() }
                }
            }
    }
}

extension ButtonStyle where Self == SoulPressableStyle {
    /// Default press: the surface dims, a soft haptic on touch-down.
    static var soulPressable: SoulPressableStyle { SoulPressableStyle() }

    /// Dim only — for CTAs that fire their own (stronger) haptic in the action.
    static var soulPressableQuiet: SoulPressableStyle { SoulPressableStyle(hapticOnPress: false) }
}

// MARK: - Pressable card (Button wrapper for former onTapGesture cards)

/// Wraps arbitrary content in a pressable Button. Use for cards that used to
/// be `onTapGesture` views — this adds the press response, the haptic and
/// proper accessibility traits in one move.
struct PressableCard<Content: View>: View {
    var haptic: Bool = true
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) { content }
            .buttonStyle(SoulPressableStyle(hapticOnPress: haptic))
    }
}
