//
//  Parallax.swift
//  Soulfull Gatherings
//
//  Scroll-driven depth. Imagery drifts gently against scroll direction so
//  cards read as windows, not stickers. GPU-only (`visualEffect`) — no
//  preference keys, no state.
//

import SwiftUI

private struct ScrollParallaxModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Total drift in points across the viewport.
    var strength: CGFloat

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.visualEffect { effect, proxy in
                let frame = proxy.frame(in: .scrollView(axis: .vertical))
                let viewport = proxy.bounds(of: .scrollView(axis: .vertical))?.height ?? frame.height
                // -0.5…0.5 as the view crosses the viewport.
                let unit = ((frame.midY / max(viewport, 1)) - 0.5)
                return effect.offset(y: -unit.clamped(to: -0.6...0.6) * strength)
            }
        }
    }
}

extension View {
    /// Drift against vertical scroll. Apply to imagery *inside* a clipped
    /// container, and overscale the image (`.scaleEffect(1.12)` or generous
    /// `scaledToFill`) so edges never show.
    func scrollParallax(strength: CGFloat = 16) -> some View {
        modifier(ScrollParallaxModifier(strength: strength))
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
