//
//  Theme.swift
//  Soulfull Gatherings
//
//  Brand palette + typography + reusable gradient helpers.
//  Colors are translated from the original oklch tokens to sRGB.
//

import SwiftUI

enum Theme {

    // MARK: - Colors

    /// Near-black canvas with a faint olive tint — matches `bg` in tokens.js.
    static let bg = Color(red: 0.043, green: 0.047, blue: 0.027)

    /// Slightly lifted surface — used for nav/header strokes.
    static let bgDeep = Color(red: 0.063, green: 0.069, blue: 0.039)

    /// Card background when not using a material.
    static let surface = Color(red: 0.082, green: 0.090, blue: 0.051)

    /// Hairline.
    static let line = Color.white.opacity(0.10)

    /// The Soulfull logo's olive-green — used as primary accent.
    static let accent = Color(red: 0.244, green: 0.263, blue: 0.082)

    /// Lifted sage for selected states.
    static let accentSoft = Color(red: 0.467, green: 0.502, blue: 0.231)

    /// Warm cream — primary text on dark.
    static let ink = Color(red: 0.961, green: 0.953, blue: 0.910)

    /// Muted ink — secondary text.
    static let inkSoft = Color(red: 0.788, green: 0.773, blue: 0.690)

    /// Tertiary text / metadata.
    static let muted = Color(red: 0.478, green: 0.463, blue: 0.388)

    /// Honey glow for selected onboarding cards.
    static let honey = Color(red: 0.898, green: 0.780, blue: 0.400)

    // MARK: - Gradients

    /// Brand splash — amber→sage→coal, used on the Welcome splash.
    static let splash = LinearGradient(
        colors: [
            Color(red: 0.302, green: 0.325, blue: 0.110),
            Color(red: 0.244, green: 0.263, blue: 0.082),
            Color(red: 0.173, green: 0.188, blue: 0.063)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Universal dark-vignette overlay used over photo backgrounds.
    static let photoVignette = LinearGradient(
        colors: [
            Color.black.opacity(0.22),
            Color.black.opacity(0.46),
            Color.black.opacity(0.66)
        ],
        startPoint: .top, endPoint: .bottom
    )

    // MARK: - Typography

    /// Serif headline — falls back to system serif if New York is unavailable.
    static func headline(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Default UI font (SF Pro).
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Tracked eyebrow caps.
    static func eyebrow(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    // MARK: - Shape

    static let cardRadius: CGFloat = 22
    static let pillRadius: CGFloat = 999
}

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8)  & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255
        )
    }
}

// MARK: - Convenient text styles

extension Text {
    /// Tracked, uppercase caption (the "eyebrow" pattern used throughout the design).
    func sgEyebrow(color: Color = Theme.inkSoft, tracking: CGFloat = 2) -> some View {
        self.font(Theme.eyebrow(11))
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
