//
//  Pressable.swift
//  Soulfull Gatherings
//
//  Touch physics. Every tappable surface in the app goes through one of
//  these styles so weight and haptics are consistent: touch-down squishes
//  with a soft spring and a light haptic; release springs back.
//

import SwiftUI

// MARK: - Pressable button style

struct SoulPressableStyle: ButtonStyle {
    /// How far the surface sinks. Cards ~0.97, small chips ~0.92.
    var scale: CGFloat = 0.97
    /// Haptic fired on touch-down. Actions should not double-fire `tap`.
    var hapticOnPress: Bool = true
    var dim: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(dim && configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.32, dampingFraction: 0.65), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    Haptics.prepare()
                    if hapticOnPress { Haptics.tap() }
                }
            }
    }
}

extension ButtonStyle where Self == SoulPressableStyle {
    /// Default card/row press: 0.97 squish + light haptic on touch-down.
    static var soulPressable: SoulPressableStyle { SoulPressableStyle() }

    /// Smaller surfaces (chips, icons) sink further so the response reads.
    static var soulPressableChip: SoulPressableStyle { SoulPressableStyle(scale: 0.92) }

    /// Squish only — for CTAs that fire their own (stronger) haptic in the action.
    static var soulPressableQuiet: SoulPressableStyle { SoulPressableStyle(hapticOnPress: false) }
}

// MARK: - Pressable card (Button wrapper for former onTapGesture cards)

/// Wraps arbitrary content in a pressable Button. Use for cards that used to
/// be `onTapGesture` views — this adds press physics, haptics, and proper
/// accessibility traits in one move.
struct PressableCard<Content: View>: View {
    var scale: CGFloat = 0.97
    var haptic: Bool = true
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) { content }
            .buttonStyle(SoulPressableStyle(scale: scale, hapticOnPress: haptic))
    }
}
