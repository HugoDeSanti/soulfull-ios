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

    @State private var pressed = false

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
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
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
                .scaleEffect(1.06)
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
        .ignoresSafeArea()
    }
}

// MARK: - Small circular icon button (back / close)

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
