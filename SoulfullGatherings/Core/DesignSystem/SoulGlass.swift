//
//  SoulGlass.swift
//  Soulfull Gatherings
//
//  The one place that knows how a surface is made: a dark veil (a light
//  frost under a black wash) with a hairline, square-cornered. It is the
//  same on every OS. Liquid Glass was dropped on purpose: its lensing,
//  specular edges and touch-bounce read as playful, and the app is meant
//  to be still. Feature code calls `.soulGlass(in:)` / `.soulGlassCard()`
//  and never builds a surface by hand.
//

import SwiftUI

private struct SoulGlassModifier<S: Shape & InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var stroke: Color

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // The frost keeps type legible over a photograph; the
                    // black over it keeps the surface from turning grey on
                    // the black canvas.
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Theme.bg.opacity(0.5))
                    if let tint { shape.fill(tint) }
                }
            }
            .overlay(shape.strokeBorder(stroke, lineWidth: Theme.hairline))
            // A surface answers taps across its whole frame, not only where
            // its text and glyphs draw (rendering gotcha 5).
            .contentShape(shape)
    }
}

extension View {
    /// A veiled surface in `shape`. Almost always a `Rectangle()`; a
    /// `Circle()` only for the round things (faces, dots, the breath circle).
    func soulGlass(
        in shape: some Shape & InsettableShape,
        tint: Color? = nil,
        stroke: Color = Theme.glassBorder
    ) -> some View {
        modifier(SoulGlassModifier(shape: shape, tint: tint, stroke: stroke))
    }

    /// A square veiled surface — cards, bars, chips, panels.
    func soulGlassCard(tint: Color? = nil, stroke: Color = Theme.glassBorder) -> some View {
        soulGlass(in: Rectangle(), tint: tint, stroke: stroke)
    }
}
