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

// MARK: - Film grain

private struct FilmGrainModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var intensity: Double

    func body(content: Content) -> some View {
        if reduceMotion {
            content.colorEffect(ShaderLibrary.filmGrain(.float(0), .float(intensity)))
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 18.0)) { timeline in
                content.colorEffect(
                    ShaderLibrary.filmGrain(.float(shaderTime(timeline.date)), .float(intensity))
                )
            }
        }
    }
}

extension View {
    /// Breathing photographic grain. Use on photo backdrops, not on text or
    /// system surfaces. Keep `intensity` ≈ 0.04–0.08.
    func filmGrain(intensity: Double = 0.055) -> some View {
        modifier(FilmGrainModifier(intensity: intensity))
    }
}

// MARK: - Aurora backdrop

/// A slowly drifting tonal field across three brand tones. The signature
/// "alive" backdrop for splash, loading, players, and empty states.
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var toneA: Color = Color(red: 0.10, green: 0.12, blue: 0.05)   // deep olive
    var toneB: Color = Color(red: 0.24, green: 0.27, blue: 0.10)   // brand accent
    var toneC: Color = Color(red: 0.36, green: 0.31, blue: 0.13)   // dim honey
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

// MARK: - Shimmer sweep

private struct ShimmerModifier: ViewModifier, Animatable {
    var progress: Double
    var intensity: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.layerEffect(
            ShaderLibrary.shimmer(.boundingRect, .float(progress), .float(intensity)),
            maxSampleOffset: .zero,
            isEnabled: progress > 0.001 && progress < 0.999
        )
    }
}

extension View {
    /// Diagonal specular sweep, driven by `progress` 0→1. Animate the bound
    /// value to play it.
    func shimmerSweep(progress: Double, intensity: Double = 0.5) -> some View {
        modifier(ShimmerModifier(progress: progress, intensity: intensity))
    }
}

/// Plays one shimmer sweep when `trigger` changes (e.g. selection).
private struct ShimmerOnChange<T: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: T
    var intensity: Double
    @State private var progress: Double = 0

    func body(content: Content) -> some View {
        content
            .shimmerSweep(progress: progress, intensity: intensity)
            .onChange(of: trigger) {
                guard !reduceMotion else { return }
                progress = 0
                withAnimation(.easeInOut(duration: 0.7)) { progress = 1 }
            }
    }
}

extension View {
    func shimmer(on trigger: some Equatable, intensity: Double = 0.5) -> some View {
        modifier(ShimmerOnChange(trigger: trigger, intensity: intensity))
    }
}

// MARK: - Noise dissolve transition

private struct NoiseDissolveModifier: ViewModifier, Animatable {
    /// 0 = fully visible, 1 = fully dissolved.
    var progress: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.layerEffect(
            ShaderLibrary.noiseDissolve(.float(progress), .float(110)),
            maxSampleOffset: .zero,
            isEnabled: progress > 0.001
        )
    }
}

/// Organic dissolve used for stage-level changes (welcome → onboarding →
/// main). Reduce Motion fallback happens at the call site via `soulStage`.
struct NoiseDissolve: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(NoiseDissolveModifier(progress: phase.isIdentity ? 0 : 1))
    }
}

extension AnyTransition {
    /// The app's stage transition: noise dissolve, or opacity under Reduce Motion.
    @MainActor
    static func soulStage(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : AnyTransition(NoiseDissolve())
    }
}

// MARK: - Editorial rise (blur + lift reveal)

private struct BlurRiseModifier: ViewModifier, Animatable {
    /// 0 = settled, 1 = fully hidden (blurred, dropped, transparent).
    var progress: Double
    var lift: CGFloat

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(1 - progress)
            .blur(radius: progress * 9)
            .offset(y: progress * lift)
    }
}

extension AnyTransition {
    /// The app's text/content reveal: rises out of a blur.
    /// ⚠️ The blur keeps a Metal filter attached even at radius 0, so this
    /// (like all blur-carrying transitions) must never wrap UIKit-backed
    /// views — TextField, NavigationStack, video. Use `editorialPageSoft`
    /// for those subtrees.
    static var editorialRise: AnyTransition {
        .modifier(active: BlurRiseModifier(progress: 1, lift: 18),
                  identity: BlurRiseModifier(progress: 0, lift: 18))
    }

    /// Paired slide handoff: new content rises in while old sinks away.
    /// Same platform-view caveat as `editorialRise`.
    static var editorialPage: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurRiseModifier(progress: 1, lift: 22),
                                 identity: BlurRiseModifier(progress: 0, lift: 22)),
            removal: .modifier(active: BlurRiseModifier(progress: 1, lift: -14),
                               identity: BlurRiseModifier(progress: 0, lift: -14))
        )
    }

    /// Blur-free page handoff — safe over platform-backed views (text fields).
    static var editorialPageSoft: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 22).combined(with: .opacity),
            removal: .offset(y: -14).combined(with: .opacity)
        )
    }
}

// MARK: - Ripple

private struct RippleModifier: ViewModifier, Animatable {
    var progress: Double
    var origin: CGPoint
    var amplitude: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.distortionEffect(
            ShaderLibrary.ripple(
                .float2(Float(origin.x), Float(origin.y)),
                .float(progress),
                .float(amplitude),
                .float(60)
            ),
            maxSampleOffset: CGSize(width: amplitude * 2, height: amplitude * 2),
            isEnabled: progress > 0.001 && progress < 0.999
        )
    }
}

extension View {
    /// Radial wave from `origin` (view-local points), settling flat at
    /// `progress` 1. Animate the bound value to play it.
    func ripple(progress: Double, origin: CGPoint, amplitude: Double = 10) -> some View {
        modifier(RippleModifier(progress: progress, origin: origin, amplitude: amplitude))
    }
}
