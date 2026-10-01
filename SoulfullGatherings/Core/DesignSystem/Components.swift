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
        // The dimming above is only how it looks. Without this VoiceOver
        // announced a live button that did nothing when activated, and the
        // press still squished. The look is unchanged: the label draws its own
        // dim, and the style doesn't read `isEnabled`.
        .disabled(!enabled)
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
    /// What the action button is *called*, as distinct from what it says.
    ///
    /// Every one of these reads "ALL", which is fine to look at under its own
    /// heading and useless to hear: a screen with two of them announces "ALL,
    /// button" twice with nothing to tell them apart. Falls back to the visible
    /// text, so a screen with only one is unaffected.
    var actionLabel: String? = nil
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
                .accessibilityLabel(actionLabel ?? action)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Blurred photo backdrop (welcome / onboarding / home / finish)

struct PhotoBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Either a bundled asset name or a `bucket/path.jpg` in Supabase Storage —
    /// `ImageSource` routes on the shape, so the static backdrops ("home-bg")
    /// and a data-driven retreat photo both arrive here as a plain String and
    /// no call site had to change.
    let imageName: String
    /// 0 = sharp, higher = more blur. Default lightly blurred per the prototype.
    var blur: CGFloat = 5
    var darken: Double = 0.5
    /// Horizontal camera pan, -1…1. Animate across paged content for parallax.
    /// Ignored under Reduce Motion: the camera holds still.
    var pan: CGFloat = 0
    /// Extra darkening across the top band, fading out by `topScrimHeight`.
    ///
    /// The vignette below is at its lightest up top (0.18) — which is exactly
    /// where every screen puts its header — so cream type over a bright sky
    /// had nothing to sit on. This gives it a ground. Pass 0 on a screen whose
    /// top is deliberately empty and whose photo should stay open.
    var topScrim: Double = 0.45
    var topScrimHeight: CGFloat = 340

    var body: some View {
        // Under Reduce Motion the photo neither pans nor zooms between pages:
        // a 10% zoom plus a sideways slide is exactly the large, unrequested
        // movement the setting asks apps to drop.
        let pan = reduceMotion ? 0 : self.pan
        return ZStack {
            // Solid floor so the blur edges don't bleed transparent.
            Theme.bg
            // The image lives in an overlay of a proposal-sized Color so
            // `scaledToFill` can only overflow *drawing*, never layout —
            // otherwise a wide-ish asset inflates the enclosing ZStack and
            // pushes sibling content past the screen edges.
            Color.clear
                .overlay {
                    CatalogImage(imageName) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: blur)
                            .saturation(1.15)
                            .brightness(-0.05)
                            .scaleEffect(pan == 0 ? 1.06 : 1.16)
                            .offset(x: -pan * 22)
                    }
                }
                .clipped()
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
        .overlay(alignment: .top) {
            if topScrim > 0 {
                LinearGradient(
                    colors: [.black.opacity(topScrim), .black.opacity(topScrim * 0.47), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: topScrimHeight)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Type over photography

extension View {
    /// Legibility treatment for type that sits directly on a photo rather than
    /// on glass or a card.
    ///
    /// Two shadows, no box: a tight one for edge definition against busy
    /// detail, and a wide, weaker halo that darkens the pixels immediately
    /// around the glyphs. Both vanish over an already-dark ground, so this is
    /// safe to apply to any photo-backed text block — it only shows up where
    /// the image underneath is bright.
    ///
    /// The rest of the rule, so photo-backed headers read the same everywhere:
    /// eyebrows in `Theme.inkSoft` (never `Theme.muted`, which sinks into the
    /// scrim) and sublines in `Theme.inkOnPhoto` at `Theme.body(14)`. Type on
    /// glass needs none of this — the surface is its own ground.
    ///
    /// Apply it to text blocks only. A `.shadow` over a UIKit-backed view
    /// (`TextField`, `TextEditor`, video) forces an offscreen pass on a view
    /// that can't be composited that way — see the rendering gotchas in
    /// CLAUDE.md — so wrap the copy, not the container that holds the field.
    func onPhoto() -> some View {
        self
            .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
            .shadow(color: .black.opacity(0.4), radius: 12)
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
                // Without this the button only hit-tests the drawn glyph — an
                // Image stretched by `.frame` leaves the surrounding area
                // non-interactive, and `glassEffect` (iOS 26) contributes no
                // hit-testable fill the way `.ultraThinMaterial` did. Every
                // CircleIconButton in the app was a ~11pt target inside a 38pt
                // circle; the account sheet's close button is where it showed.
                .contentShape(Circle())
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
                    .foregroundStyle(Theme.inkSoft)
                Text(headline)
                    .font(Theme.headline(34))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .kerning(-0.3)
                    .frame(maxWidth: 320)
                Text(message)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
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
