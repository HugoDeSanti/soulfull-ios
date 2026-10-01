//
//  Parallax.swift
//  Soulfull Gatherings
//
//  Scroll-driven motion helpers.
//
//  Note for future depth effects: `visualEffect` offsets/scales are applied
//  outside ancestor clips — a parallax image inside a clipped card bleeds
//  past the card bounds (we shipped and reverted exactly that). Scroll-
//  driven imagery motion is only safe on full-bleed, unclipped surfaces;
//  cards get their motion from `listReveal`/`scrollTransition` (which offset
//  the whole, unclipped card) instead.
//

import SwiftUI

extension View {
    /// Standard list-row entrance: rows rise and fade in as they enter from
    /// the bottom of the viewport. Interactive (scrubs with the scroll). Under
    /// Reduce Motion they only fade.
    func listReveal() -> some View {
        modifier(ListReveal())
    }
}

private struct ListReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let rise: CGFloat = reduceMotion ? 0 : 18
        return content
            .scrollTransition(.interactive(timingCurve: .easeOut), axis: .vertical) { view, phase in
                let entering = max(phase.value, 0)
                return view
                    .opacity(1 - entering * 0.5)
                    .offset(y: entering * rise)
            }
    }
}
