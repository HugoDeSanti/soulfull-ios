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
    var axis: Axis

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.visualEffect { [axis] effect, proxy in
                let frame = proxy.frame(in: .scrollView(axis: axis))
                let bounds = proxy.bounds(of: .scrollView(axis: axis))
                // -0.5…0.5 as the view crosses the viewport.
                switch axis {
                case .vertical:
                    let viewport = bounds?.height ?? frame.height
                    let unit = ((frame.midY / max(viewport, 1)) - 0.5)
                    return effect.offset(y: -unit.clamped(to: -0.6...0.6) * strength)
                case .horizontal:
                    let viewport = bounds?.width ?? frame.width
                    let unit = ((frame.midX / max(viewport, 1)) - 0.5)
                    return effect.offset(x: -unit.clamped(to: -0.6...0.6) * strength)
                }
            }
        }
    }
}

extension View {
    /// Drift against scroll. Apply to imagery *inside* a clipped container,
    /// and overscale the image (`.scaleEffect(1.12)` or generous
    /// `scaledToFill`) so edges never show.
    func scrollParallax(strength: CGFloat = 16, axis: Axis = .vertical) -> some View {
        modifier(ScrollParallaxModifier(strength: strength, axis: axis))
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
