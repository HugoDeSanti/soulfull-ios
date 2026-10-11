//
//  Theme.swift
//  Soulfull Gatherings
//
//  Brand palette, typography, shape, space and motion.
//  Colours are hand-picked sRGB (the palette follows the Open app's: black,
//  near-white, and colour only in photography and the atmosphere washes).
//

import SwiftUI

enum Theme {

    // MARK: - Colors
    //
    // Near-white over photography: the colour comes from the photo
    // backdrops, never from the chrome. Ember (a copper) is the one warm
    // mark; moss (the logo's olive) the quiet positive one.

    /// True black — the canvas under the photo backdrops, and the ground of
    /// the few pages without one (the recipe and digital retreat pages).
    static let bg = Color.black

    /// The docked bar's ground, one step off black so the bar has an edge.
    static let bgDeep = Color(red: 0.035, green: 0.035, blue: 0.031)

    /// Card fill when a surface needs one — a lifted black, barely warm.
    static let surface = Color(red: 0.063, green: 0.063, blue: 0.055)

    /// Hairline — rules between sections and rows.
    static let line = Color.white.opacity(0.10)

    /// Standard surface stroke.
    static let glassBorder = Color.white.opacity(0.12)

    /// Stronger stroke — ghost buttons, active states.
    static let glassBorderHigh = Color.white.opacity(0.22)

    /// The Soulfull logo's olive-green — the moss atmosphere's deep tone.
    static let accent = Color(red: 0.244, green: 0.263, blue: 0.082)

    /// Lifted moss — the moss atmosphere's light tone, and quiet positive marks.
    static let accentSoft = Color(red: 0.490, green: 0.529, blue: 0.220)

    /// Near-white with the faintest warmth — primary text.
    static let ink = Color(red: 0.949, green: 0.945, blue: 0.929)

    /// Light warm grey — secondary text. As bright as the old cream's
    /// secondary: a darker grey (0.63) read well on black but sank into the
    /// photo backdrops' skies.
    static let inkSoft = Color(red: 0.788, green: 0.780, blue: 0.757)

    /// Tertiary text / metadata. On glass or a card only — over
    /// photography it sinks into the image; use `inkSoft` there (see
    /// `View.onPhoto()`).
    static let muted = Color(red: 0.490, green: 0.482, blue: 0.463)

    /// Body copy that sits directly on photography rather than on glass.
    /// Brighter than `inkSoft`, which washes out over a pale sky — the one
    /// colour for every photo-backed subline in the app.
    static let inkOnPhoto = ink.opacity(0.92)

    /// Copper — the one warm mark: what's selected, what's new, what's yours
    /// today. Used sparingly; most active states are simply `ink`.
    static let ember = Color(red: 0.816, green: 0.549, blue: 0.369)

    /// Muted brick for irreversible actions (Delete account) — quiet enough
    /// for the black ground, unmistakable next to ink.
    static let danger = Color(red: 0.85, green: 0.36, blue: 0.33)

    // MARK: - Gradients

    /// Brand splash — moss falling to black, top to bottom.
    static let splash = LinearGradient(
        colors: [
            Color(red: 0.267, green: 0.294, blue: 0.086),
            Color(red: 0.122, green: 0.133, blue: 0.047),
            Color.black
        ],
        startPoint: .top, endPoint: .bottom
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

    /// Display headline — Geist at the requested weight.
    static func headline(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(geistName(for: weight), size: size)
    }

    /// Body / UI text — Geist at the requested weight.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(geistName(for: weight), size: size)
    }

    /// Tracked eyebrow caps — Geist Regular.
    static func eyebrow(_ size: CGFloat = 11) -> Font {
        .custom("Geist-Regular", size: size)
    }

    /// Maps `Font.Weight` to the matching Geist PostScript name.
    /// Only Thin, Light, Regular, Medium, SemiBold, and Bold are shipped — heavier weights fall through to Bold.
    private static func geistName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin:       return "Geist-Thin"
        case .light:                   return "Geist-Light"
        case .medium:                  return "Geist-Medium"
        case .semibold:                return "Geist-SemiBold"
        case .bold, .heavy, .black:    return "Geist-Bold"
        default:                       return "Geist-Regular"
        }
    }

    // MARK: - Shape
    //
    // There are no rounded corners. Rounding read as playful; a surface here
    // is cut square like a printed page — photographs, cards, buttons and
    // sheets alike. Only a face (`AvatarView`), a dot and the player's breath
    // circle are round.

    /// The stroke around a surface or a ghost button.
    static let hairline: CGFloat = 0.75

    // MARK: - Space
    //
    // Empty space is part of the layout, not what's left over.

    /// The page's side margin.
    static let gutter: CGFloat = 24

    /// Between the sections of a page.
    static let sectionGap: CGFloat = 64

    /// From a tab's header (its title and subline) to the first thing on the
    /// page, measured to what shows. Every tab opens the same way; they had
    /// drifted to 36, 56 and 64.
    static let headerGap: CGFloat = 40

    // MARK: - Motion
    //
    // Still motion: things fade in and settle, at breath pace. Nothing
    // springs, bounces, squishes or overshoots — every curve is an ease.

    enum Motion {
        /// A finger landing — the surface dims; it never moves.
        static let press = Animation.easeOut(duration: 0.12)
        /// The finger lifting — the surface comes back slowly.
        static let release = Animation.easeInOut(duration: 0.5)
        /// A state settling: a selection, a toggle, a count, a panel.
        static let settle = Animation.easeInOut(duration: 0.6)
        /// Content arriving — a fade, as at the end of an exhale.
        static let reveal = Animation.easeOut(duration: 1.1)
        /// A stage handing over (loading → welcome → onboarding → main).
        static let stage = Animation.easeInOut(duration: 1.2)
        /// One breath — the period of every idle loop (atmospheres, halos).
        static let breath: Double = 6
    }
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
