//
//  SoulGlass.swift
//  Soulfull Gatherings
//
//  The one place that knows how a surface is made: a light frost with a
//  hairline, square-cornered, the same on every OS. The photograph behind
//  it shows through. (A black wash over the frost was tried and removed at
//  the owner's request: it turned every card into a dark slab over the
//  backdrop.) Liquid Glass was dropped on purpose: its lensing, specular
//  edges and touch-bounce read as playful, and the app is meant to be
//  still. Feature code calls `.soulGlass(in:)` / `.soulGlassCard()` and
//  never builds a surface by hand.
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
                    shape.fill(.ultraThinMaterial)
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
    /// A frosted surface in `shape`. Almost always a `Rectangle()`; a
    /// `Circle()` only for the round things (faces, dots, the breath circle).
    func soulGlass(
        in shape: some Shape & InsettableShape,
        tint: Color? = nil,
        stroke: Color = Theme.glassBorder
    ) -> some View {
        modifier(SoulGlassModifier(shape: shape, tint: tint, stroke: stroke))
    }

    /// A square frosted surface — cards, bars, chips, panels.
    func soulGlassCard(tint: Color? = nil, stroke: Color = Theme.glassBorder) -> some View {
        soulGlass(in: Rectangle(), tint: tint, stroke: stroke)
    }
}
