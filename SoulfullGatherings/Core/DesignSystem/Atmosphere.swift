//
//  Atmosphere.swift
//  Soulfull Gatherings
//
//  A single-hue wash falling from the top edge into black, like light
//  through a doorway, as the Open app lays its copper daily card. Today it
//  is Home's ritual card. It was briefly the ground of every screen in place
//  of the photo backdrops, which read as a dark veil over the app and was
//  reverted the same day (2026-10-10): pages keep their `PhotoBackdrop`.
//
//  It breathes: the wash brightens and settles over two breaths, and holds
//  still under Reduce Motion. Nothing else about it moves.
//

import SwiftUI

struct Atmosphere: View {
    enum Tone {
        /// The logo's olive. The default — home ground for the brand.
        case moss
        /// Copper falling to umber. Warmth: the gatherings, a guide.
        case ember
        /// A dusky rose. People: community, friends.
        case dusk
        /// A blue-black slate. Night: sleep, stillness, the player at rest.
        case slate

        /// The wash, top to bottom: tone → black. Dim enough at the top
        /// that ink keeps its contrast over it.
        fileprivate var stops: [Gradient.Stop] {
            let (top, mid, low) = colors
            return [
                .init(color: top, location: 0),
                .init(color: mid, location: 0.38),
                .init(color: low, location: 0.72),
                .init(color: .black, location: 1),
            ]
        }

        private var colors: (Color, Color, Color) {
            switch self {
            case .moss:  (Color(red: 0.239, green: 0.267, blue: 0.086),
                          Color(red: 0.149, green: 0.169, blue: 0.051),
                          Color(red: 0.067, green: 0.075, blue: 0.039))
            case .ember: (Color(red: 0.400, green: 0.200, blue: 0.086),
                          Color(red: 0.239, green: 0.114, blue: 0.043),
                          Color(red: 0.102, green: 0.043, blue: 0.016))
            case .dusk:  (Color(red: 0.365, green: 0.192, blue: 0.173),
                          Color(red: 0.212, green: 0.102, blue: 0.098),
                          Color(red: 0.086, green: 0.039, blue: 0.039))
            case .slate: (Color(red: 0.141, green: 0.180, blue: 0.247),
                          Color(red: 0.082, green: 0.106, blue: 0.149),
                          Color(red: 0.035, green: 0.043, blue: 0.063))
            }
        }
    }

    var tone: Tone = .moss
    /// How far down the view the wash reaches before it's black, 0…1.
    var reach: CGFloat = 0.5
    /// The wash's strength over black, 0…1. A page's ground stays quiet —
    /// a hint of colour behind the header, the rest black — so photographs
    /// and the one card that carries a full wash (Home's ritual) hold the
    /// colour. A card passes 1.
    var intensity: Double = 0.55
    /// A page's ground runs under the status bar and the home indicator; a
    /// card's wash stays inside the card.
    var fillsScreen: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inhale = false

    var body: some View {
        ZStack {
            Theme.bg
            LinearGradient(stops: tone.stops,
                           startPoint: .top,
                           endPoint: UnitPoint(x: 0.5, y: reach))
                .opacity(intensity * (inhale ? 1 : 0.78))
        }
        .ignoresSafeArea(edges: fillsScreen ? .all : [])
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil
                   : .easeInOut(duration: Theme.Motion.breath * 2).repeatForever(autoreverses: true),
                   value: inhale)
        .onAppear { if !reduceMotion { inhale = true } }
    }
}

#Preview {
    HStack(spacing: 0) {
        Atmosphere(tone: .moss)
        Atmosphere(tone: .ember)
        Atmosphere(tone: .dusk)
        Atmosphere(tone: .slate)
    }
    .preferredColorScheme(.dark)
}
