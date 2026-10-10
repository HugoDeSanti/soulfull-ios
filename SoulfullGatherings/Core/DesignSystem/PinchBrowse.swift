//
//  PinchBrowse.swift
//  Soulfull Gatherings
//
//  The magazine "zoom out" interaction. Attach to any scrolling catalog
//  whose layout branches on a `zoomedOut` flag (1-column feature spread vs
//  multi-column contact sheet — a LazyVGrid with stable IDs animates the
//  morph for free). The pinch is interactive: live magnification scrubs
//  scale/blur, then commits the flag with a slow ease and a haptic.
//

import SwiftUI

private struct PinchBrowsableModifier: ViewModifier {
    @Binding var zoomedOut: Bool
    @State private var pinch: CGFloat = 1

    private let commit = Theme.Motion.settle

    /// Temporary scale while fingers are down; exactly 1 at rest.
    private var scrub: CGFloat {
        if zoomedOut {
            return max(1, min(1.05, pinch))          // swelling toward feature
        } else {
            return min(1, max(0.9, 0.9 + 0.1 * pinch)) // receding toward sheet
        }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scrub)
            .blur(radius: abs(1 - scrub) * 26)
            // High priority so a two-finger pinch cancels card buttons
            // underneath instead of also tapping one of them; one-finger
            // scrolling never matches the magnify and passes through.
            .highPriorityGesture(
                MagnifyGesture()
                    .onChanged { value in
                        pinch = value.magnification
                        if pinch < 0.97 || pinch > 1.03 { Haptics.prepare() }
                    }
                    .onEnded { value in
                        let m = value.magnification
                        withAnimation(commit) {
                            if !zoomedOut, m < 0.8 {
                                Haptics.bump()
                                zoomedOut = true
                            } else if zoomedOut, m > 1.25 {
                                Haptics.bump()
                                zoomedOut = false
                            }
                            pinch = 1
                        }
                    }
            )
    }
}

extension View {
    /// Pinch out → `zoomedOut` true (contact sheet), pinch in → false.
    /// Pair with a non-gesture affordance (a grid toggle button) for
    /// discoverability.
    func pinchBrowsable(zoomedOut: Binding<Bool>) -> some View {
        modifier(PinchBrowsableModifier(zoomedOut: zoomedOut))
    }
}
