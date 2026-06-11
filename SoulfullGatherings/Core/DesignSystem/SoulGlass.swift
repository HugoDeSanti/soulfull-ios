//
//  SoulGlass.swift
//  Soulfull Gatherings
//
//  The one place that knows how glass is made. On iOS 26+ this is real
//  Liquid Glass (`glassEffect`); on iOS 18–25 it's the material + hairline
//  look the app shipped with. Feature code calls `.soulGlass(in:)` and never
//  branches on OS version.
//

import SwiftUI

private struct SoulGlassModifier<S: Shape & InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool
    var stroke: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(stroke, lineWidth: 1))
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

extension View {
    /// Liquid glass on iOS 26+, material + hairline below. `interactive`
    /// opts into the touch-responsive glass highlight (buttons, nav).
    func soulGlass(
        in shape: some Shape & InsettableShape,
        tint: Color? = nil,
        interactive: Bool = false,
        stroke: Color = Theme.glassBorder
    ) -> some View {
        modifier(SoulGlassModifier(shape: shape, tint: tint, interactive: interactive, stroke: stroke))
    }

    /// Capsule convenience — pills, chips, bars.
    func soulGlassCapsule(tint: Color? = nil, interactive: Bool = false,
                          stroke: Color = Theme.glassBorder) -> some View {
        soulGlass(in: Capsule(), tint: tint, interactive: interactive, stroke: stroke)
    }

    /// Card convenience — `Theme.cardRadius` continuous corners.
    func soulGlassCard(radius: CGFloat = Theme.cardRadius, tint: Color? = nil,
                       stroke: Color = Theme.glassBorder) -> some View {
        soulGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous),
                  tint: tint, stroke: stroke)
    }
}
