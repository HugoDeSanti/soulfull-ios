//
//  Components.swift
//  Soulfull Gatherings
//
//  Reusable building blocks — buttons, veiled cards, image backdrops,
//  section labels. Anything used by 2+ screens lives here. Every shape is
//  square (see `Theme` → Shape) and every motion an ease (→ Motion).
//

import SwiftUI

// MARK: - Primary button (square: a hairline in ink, or filled ink)

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
                Rectangle()
                    .fill(filled ? Theme.ink : Color.clear)
                    .overlay(
                        Rectangle().strokeBorder(Theme.ink.opacity(0.7), lineWidth: filled ? 0 : Theme.hairline)
                    )
            )
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoulPressableStyle(hapticOnPress: false))
        // The dimming above is only how it looks. Without this VoiceOver
        // announced a live button that did nothing when activated, and the
        // press still dimmed it. The look is unchanged: the label draws its
        // own dim, and the style doesn't read `isEnabled`.
        .disabled(!enabled)
    }
}

// MARK: - Glass card (a veiled square surface)

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .soulGlassCard()
    }
}

// MARK: - Section header (a hairline, then a tracked caps label)

/// Opens a section the way a printed page does: a rule across the measure,
/// and under it a small tracked label. The size lives in the content below
/// it, not in the heading, so a page reads as quiet sections with air
/// between them rather than a stack of headlines.
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
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(Theme.line)
                .frame(height: 0.5)
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .sgEyebrow(color: Theme.ink)
                    // Shown in caps, read as written: VoiceOver spells some
                    // all-caps words out, and the heading used to be in
                    // sentence case, which is what the UI tests look for.
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let action, let onAction {
                    Button {
                        Haptics.tap()
                        onAction()
                    } label: {
                        Text(action)
                            .sgEyebrow(color: Theme.inkSoft)
                            // A 44pt target around a small caps word.
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.soulPressable)
                    .padding(.vertical, -14)
                    .accessibilityLabel(actionLabel ?? action)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
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
                            // Photography a shade quieter than life, as
                            // Open's is — warm, muted, never vivid.
                            .saturation(0.9)
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

// MARK: - Status bar scrim

extension View {
    /// A soft rise of the canvas colour behind the clock, there only once this
    /// scroll view's content has moved up under it.
    ///
    /// At rest the page runs clean to the top edge. Scrolled, cream headlines
    /// and glass chips would collide with the clock, so the band fades in over
    /// `fadeIn` points of scroll and sinks them into the canvas as they reach
    /// it — the same move as the retreat detail's and the recipe's scrims.
    ///
    /// It is only as deep as the status bar, and fades out inside it, so it
    /// covers the clock and nothing of the page. It used to be on all the
    /// time, over every screen (a near-solid slab cut across the photos), and
    /// then 40pt deeper than the status bar, which still read as a dark bar
    /// across the top of every scrolled screen.
    ///
    /// Apply it to the `ScrollView` itself, since it reads that view's scroll
    /// geometry, and before a pinned overlay such as a `PracticeBackBar`, so
    /// the bar draws above it. `reach` takes the band that far below the
    /// status bar, to sit behind a pinned bar too. A hero screen starts
    /// `fadeIn` late, so the band doesn't darken a photo nothing has reached
    /// yet.
    func statusBarScrim(fadeIn: ClosedRange<CGFloat> = 0...36, reach: CGFloat = 0) -> some View {
        modifier(StatusBarScrim(fadeIn: fadeIn, reach: reach))
    }
}

private struct StatusBarScrim: ViewModifier {
    let fadeIn: ClosedRange<CGFloat>
    let reach: CGFloat
    @State private var opacity: Double = 0

    /// The band's eased bottom edge, inside its height, so the band ends
    /// where the status bar does rather than below it.
    private static let fade: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Double.self) { geo in
                let y = geo.contentOffset.y + geo.contentInsets.top
                let t = (y - fadeIn.lowerBound) / (fadeIn.upperBound - fadeIn.lowerBound)
                // In twentieths, so a page scrolling well past the band
                // doesn't re-render this on every frame.
                return (min(1, max(0, t)) * 20).rounded() / 20
            } action: { _, new in
                opacity = new
            }
            .overlay(alignment: .top) {
                // From the top of the safe area, with the band reaching up
                // through the status bar to the screen's edge, whatever its
                // height on this device.
                Color.clear
                    .frame(height: reach)
                    .frame(maxWidth: .infinity)
                    .background { band.ignoresSafeArea(edges: .top) }
                    .opacity(opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

    /// Dense behind the clock, enough to sink cream type, then eased out over
    /// `fade`, so there's no edge to find. (A frosted material was tried: over
    /// the already-blurred backdrops it read as a flat grey slab.)
    private var band: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Theme.bg.opacity(0.92), Theme.bg.opacity(0.84)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [
                .init(color: Theme.bg.opacity(0.84), location: 0),
                .init(color: Theme.bg.opacity(0.6), location: 0.3),
                .init(color: Theme.bg.opacity(0.28), location: 0.6),
                .init(color: Theme.bg.opacity(0.08), location: 0.84),
                .init(color: Theme.bg.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fade)
        }
    }
}

// MARK: - Glyph button (back / close / view toggle)

/// A bare glyph, the way Open draws its ← and ×: no circle, no glass. The
/// tappable area is still a 44pt square around it — a glyph only answers
/// taps where it draws (rendering gotcha 5). A soft shadow keeps it legible
/// where it sits on a photograph, and vanishes on black.
struct GlyphButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .shadow(color: .black.opacity(0.45), radius: 6)
        }
        .buttonStyle(.soulPressable)
    }
}

// MARK: - Tab placeholder (shared empty-state shell for unbuilt tabs)

struct TabPlaceholder: View {
    let eyebrow: String
    let headline: String
    let message: String

    var body: some View {
        ZStack {
            Atmosphere(tone: .moss)

            VStack(spacing: 18) {
                Spacer()
                Image("soulfull-logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 72, height: 72)
                    .breathing(scale: 1...1, opacity: 0.6...0.95)
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

// MARK: - Pulse modifier (a live indicator that glows and fades)

/// Light, not size: the dot brightens and dims at half a breath. Static
/// under Reduce Motion.
struct PulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || on ? 1 : 0.35)
            .animation(.easeInOut(duration: Theme.Motion.breath / 2).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

extension View {
    func pulse() -> some View { modifier(PulseModifier()) }
}

// MARK: - Breathing (slow scale/opacity loop at breath pace)

/// The app's signature idle motion — a slow inhale/exhale. Use for logos,
/// halos, and the player's breathing circle. Keep the scale small (a few
/// percent): it should be felt more than seen. Static under Reduce Motion.
struct BreathingModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scaleRange: ClosedRange<CGFloat> = 0.98...1.02
    var opacityRange: ClosedRange<Double> = 0.8...1.0
    var period: Double = Theme.Motion.breath
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
    func breathing(scale: ClosedRange<CGFloat> = 0.98...1.02,
                   opacity: ClosedRange<Double> = 0.8...1.0,
                   period: Double = Theme.Motion.breath) -> some View {
        modifier(BreathingModifier(scaleRange: scale, opacityRange: opacity, period: period))
    }
}
