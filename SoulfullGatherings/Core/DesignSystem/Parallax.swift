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
//  cards get their motion from `listReveal`/`scrollTransition` (which fade
//  the whole card) instead.
//

import SwiftUI

extension View {
    /// Standard list-row entrance: rows fade up from half-light as they
    /// enter from the bottom of the viewport. Interactive (scrubs with the
    /// scroll). Light only — they used to rise 18pt as well; nothing travels
    /// now.
    func listReveal() -> some View {
        modifier(ListReveal())
    }
}

private struct ListReveal: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollTransition(.interactive(timingCurve: .easeOut), axis: .vertical) { view, phase in
                view.opacity(1 - max(phase.value, 0) * 0.5)
            }
    }
}
