//
//  Components.swift
//  Soulfull Gatherings
//
//  Reusable building blocks — buttons, glass cards, image backdrops,
//  section labels. Anything used by 2+ screens lives here.
//

import SwiftUI

// MARK: - Primary button (ghost pill, cream stroke on dark)

struct SGPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var filled: Bool = false
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            guard enabled else { return }
            Haptics.bump()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
                Text(title)
                    .font(Theme.body(15, weight: .medium))
                    .tracking(0.4)
            }
            .foregroundStyle(filled ? Color.black : Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(filled ? Color.white : Color.clear)
                    .overlay(
                        Capsule().strokeBorder(Theme.ink, lineWidth: filled ? 0 : 1)
                    )
            )
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Capsule())
        }
        .buttonStyle(SoulPressableStyle(scale: 0.975, hapticOnPress: false, dim: false))
    }
}

// MARK: - Glass card (system material wrapper)

struct GlassCard<Content: View>: View {
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .soulGlassCard(radius: radius)
    }
}

// MARK: - Section header (eyebrow-styled section title used on Home / Library)

struct SectionLabel: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.headline(22))
                .foregroundStyle(Theme.ink)
                .kerning(-0.2)
            Spacer()
            if let action, let onAction {
                Button {
                    Haptics.tap()
                    onAction()
                } label: {
                    Text(action)
                        .font(Theme.body(12))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSoft)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Blurred photo backdrop (welcome / onboarding / home / finish)

struct PhotoBackdrop: View {
    let imageName: String
    /// 0 = sharp, higher = more blur. Default lightly blurred per the prototype.
    var blur: CGFloat = 5
    var darken: Double = 0.5
    /// Film-grain strength; 0 disables.
    var grain: Double = 0.05
    /// Horizontal camera pan, -1…1. Animate across paged content for parallax.
    var pan: CGFloat = 0

    var body: some View {
        ZStack {
            // Solid floor so the blur edges don't bleed transparent.
            Theme.bg
            Image(imageName)
                .resizable()
                .scaledToFill()
                .blur(radius: blur)
                .saturation(1.15)
                .brightness(-0.05)
                .scaleEffect(pan == 0 ? 1.06 : 1.16)
                .offset(x: -pan * 22)
            // Top→bottom vignette for legibility.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.30),
                    Color.black.opacity(darken)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .modifier(GrainIfEnabled(intensity: grain))
        .ignoresSafeArea()
    }
}

/// Conditionally applies film grain (a no-op when intensity is 0) so
/// PhotoBackdrop call sites can tune or disable it per screen.
private struct GrainIfEnabled: ViewModifier {
    let intensity: Double
    func body(content: Content) -> some View {
        if intensity > 0 {
            content.filmGrain(intensity: intensity)
        } else {
            content
        }
    }
}

// MARK: - Small circular icon button (back / close)

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .soulGlass(in: Circle(), interactive: true, stroke: Theme.glassBorderHigh)
        }
        .buttonStyle(.soulPressableChip)
    }
}

// MARK: - Tab placeholder (shared empty-state shell for unbuilt tabs)

struct TabPlaceholder: View {
    let eyebrow: String
    let headline: String
    let message: String

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: "home-bg", blur: 4, darken: 0.7)

            // Living veil over the photo — placeholders still breathe.
            AuroraBackground(speed: 0.7)
                .opacity(0.4)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()
                Image("soulfull-logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 72, height: 72)
                    .breathing(scale: 0.95...1.05, opacity: 0.75...0.95, period: 5.5)
                Text(eyebrow.uppercased())
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.muted)
                Text(headline)
                    .font(Theme.headline(34))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .kerning(-0.3)
                    .frame(maxWidth: 320)
                Text(message)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 320)
                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Pulse modifier (white dot live-indicator, used for circles and live events)

struct PulseModifier: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1 : 0.85)
            .opacity(on ? 1 : 0.4)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

extension View {
    func pulse() -> some View { modifier(PulseModifier()) }
}

// MARK: - Breathing (slow scale/opacity loop at breath pace)

/// The app's signature idle motion — a 5–6s inhale/exhale. Use for logos,
/// halos, and the player's breathing circle. Static under Reduce Motion.
struct BreathingModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scaleRange: ClosedRange<CGFloat> = 0.94...1.06
    var opacityRange: ClosedRange<Double> = 0.85...1.0
    var period: Double = 5.5
    @State private var inhale = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (inhale ? scaleRange.upperBound : scaleRange.lowerBound))
            .opacity(reduceMotion ? 1 : (inhale ? opacityRange.upperBound : opacityRange.lowerBound))
            .animation(.easeInOut(duration: period).repeatForever(autoreverses: true), value: inhale)
            .onAppear { inhale = true }
    }
}

extension View {
    func breathing(scale: ClosedRange<CGFloat> = 0.94...1.06,
                   opacity: ClosedRange<Double> = 0.85...1.0,
                   period: Double = 5.5) -> some View {
        modifier(BreathingModifier(scaleRange: scale, opacityRange: opacity, period: period))
    }
}
