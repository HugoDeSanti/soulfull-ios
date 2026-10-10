//
//  ShaderFX.swift
//  Soulfull Gatherings
//
//  SwiftUI wrappers for Shaders.metal. Feature code uses these — never
//  ShaderLibrary directly — so Reduce Motion fallbacks and uniform scaling
//  live in exactly one place.
//

import SwiftUI

// MARK: - Shared clock

/// A bounded time value for shader uniforms (wraps hourly to keep float
/// precision healthy on long sessions).
@inline(__always)
private func shaderTime(_ date: Date) -> Double {
    date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
}

// MARK: - Aurora backdrop

/// A slowly drifting tonal field across three tones — the practice player's
/// ground, where the room is meant to feel alive. Everywhere else a screen
/// sits on the stiller `Atmosphere`.
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var toneA: Color = Color(red: 0.03, green: 0.035, blue: 0.015) // near-black moss
    var toneB: Color = Color(red: 0.24, green: 0.27, blue: 0.10)   // brand accent
    var toneC: Color = Color(red: 0.34, green: 0.18, blue: 0.08)   // umber (the ember wash)
    /// 1.0 = breath pace. Stay below 2.
    var speed: Double = 1.0

    var body: some View {
        if reduceMotion {
            LinearGradient(colors: [toneA, toneB, toneA],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                Rectangle()
                    .fill(.black)
                    .colorEffect(
                        ShaderLibrary.aurora(
                            .boundingRect,
                            .float(shaderTime(timeline.date) * 0.045 * speed),
                            .color(toneA), .color(toneB), .color(toneC)
                        )
                    )
            }
        }
    }
}

extension AuroraBackground {
    /// Aurora graded from a retreat / artwork tone triple.
    init(tones: (top: Color, mid: Color, base: Color), speed: Double = 1.0) {
        self.init(toneA: tones.base, toneB: tones.mid, toneC: tones.top, speed: speed)
    }
}

// MARK: - Stage transition

extension AnyTransition {
    /// The app's stage handoff (loading → welcome → onboarding → main): a
    /// plain crossfade, timed by `Theme.Motion.stage`. It used to be a noise
    /// dissolve, which drew attention to itself.
    static var soulStage: AnyTransition { .opacity }
}

// MARK: - Editorial reveal (a focus pull: blur + fade, nothing moves)

private struct FocusFadeModifier: ViewModifier, Animatable {
    /// 0 = settled, 1 = fully hidden (blurred, transparent).
    var progress: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(1 - progress)
            .blur(radius: progress * 8)
    }
}

extension AnyTransition {
    /// The app's text/content reveal: comes into focus where it stands, as
    /// a camera pulls focus. It used to rise 18pt as well; nothing travels
    /// now.
    /// ⚠️ The blur keeps a Metal filter attached even at radius 0, so this
    /// (like all blur-carrying transitions) must never wrap UIKit-backed
    /// views — TextField, NavigationStack, video. Use `editorialPageSoft`
    /// for those subtrees.
    static var editorialRise: AnyTransition {
        .modifier(active: FocusFadeModifier(progress: 1),
                  identity: FocusFadeModifier(progress: 0))
    }

    /// Paired page handoff: the old page loses focus as the new one finds
    /// it. Same platform-view caveat as `editorialRise`.
    static var editorialPage: AnyTransition { editorialRise }

    /// Blur-free page handoff — safe over platform-backed views (text
    /// fields): a plain crossfade.
    static var editorialPageSoft: AnyTransition { .opacity }
}
