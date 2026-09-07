//
//  WelcomeView.swift
//  Soulfull Gatherings
//
//  Splash (logo breathing over the tropical backdrop) → 3 explainer slides.
//  The backdrop pans like a slow camera move as slides advance; copy rises
//  out of a blur; a folio counter + hairline segments replace dots.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var app

    /// 0 = splash, 1...3 = explainer slides.
    @State private var step: Int = 0

    private struct Slide: Identifiable {
        let id: String
        let eyebrow: String
        let firstHalf: String
        let accentHalf: String
        let body: String
    }

    private let slides: [Slide] = [
        Slide(id: "retreats",
              eyebrow: "Digital & Physical Retreats",
              firstHalf: "Wellness retreats,",
              accentHalf: "online and around the world.",
              body: "Luxurious in-person gatherings and live digital retreats — fitness, breathwork, meditation, somatic therapy, and recovery."),
        Slide(id: "community",
              eyebrow: "A Conscious Community",
              firstHalf: "A worldwide community",
              accentHalf: "that travels, heals, and connects.",
              body: "A conscious space for honest conversation and shared practice."),
        Slide(id: "soulai",
              eyebrow: "Soul AI",
              firstHalf: "Meet Soul,",
              accentHalf: "your companion through the journey.",
              body: "A private guide for check-ins, reflections, and practices shaped to how you feel today.")
    ]

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: "welcome-bg", blur: 6, darken: 0.62,
                          pan: CGFloat(step) / CGFloat(max(slides.count, 1)))

            if step == 0 {
                splash
                    .transition(.editorialRise)
            } else {
                slideStack
                    .transition(.editorialRise)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if step == 0 {
                Haptics.tap()
                step = 1
            }
        }
        .animation(.spring(response: 0.65, dampingFraction: 0.85), value: step)
    }

    // MARK: - Splash

    private var splash: some View {
        ZStack {
            // Halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.96).opacity(0.20), .clear],
                        center: .center, startRadius: 30, endRadius: 280
                    )
                )
                .frame(width: 520, height: 520)
                .blur(radius: 24)
                .breathing(scale: 0.82...1.22, opacity: 0.35...0.65, period: 5.5)

            // Wordmark
            Image("soulfull-logo-white")
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .breathing(scale: 0.93...1.07, opacity: 0.84...1.0, period: 5.5)

            VStack {
                Spacer()
                Text("TAP TO CONTINUE")
                    .font(Theme.eyebrow(11))
                    .tracking(3.4)
                    .foregroundStyle(Color(white: 0.92).opacity(0.72))
                    .padding(14)
                    .onPhoto()
                    .breathing(scale: 1.0...1.0, opacity: 0.45...0.9, period: 2.8)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Slides

    @ViewBuilder
    private var slideStack: some View {
        if step > 0, step - 1 < slides.count {
        let isLast = step == slides.count
        let slide = slides[step - 1]

        VStack(alignment: .leading, spacing: 0) {
            // Top bar: logo + folio
            HStack(alignment: .top) {
                Image("soulfull-logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 56, height: 56)
                    .opacity(0.88)
                Spacer()
                folio
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                Text(slide.eyebrow.uppercased())
                    .font(Theme.eyebrow(9))
                    .tracking(3)
                    .foregroundStyle(Color(white: 0.95).opacity(0.7))

                twoTone(first: slide.firstHalf, accent: slide.accentHalf)

                Text(slide.body)
                    .font(Theme.body(13))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineSpacing(3)
            }
            .padding(.horizontal, 30)
            .onPhoto()
            .id(slide.id)
            .transition(.editorialPage)

            // Hairline progress segments
            segments
                .padding(.horizontal, 30)
                .padding(.top, 26)

            VStack(spacing: 4) {
                SGPrimaryButton(title: isLast ? "Begin" : "Next") {
                    if isLast {
                        app.beginOnboarding()
                    } else {
                        step += 1
                    }
                }
                if isLast {
                    Button {
                        app.beginOnboarding()
                    } label: {
                        Text("I already have an account")
                            .font(Theme.body(13))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .padding(12)
                    }
                    .buttonStyle(.soulPressableQuiet)
                    .transition(.editorialRise)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0, step < slides.count {
                        Haptics.select()
                        step += 1
                    } else if value.translation.width > 0, step > 1 {
                        Haptics.select()
                        step -= 1
                    }
                }
        )
        } // end if step > 0
    }

    /// Magazine folio — "02 / 03" with the current number animating.
    private var folio: some View {
        HStack(spacing: 3) {
            Text(String(format: "%02d", step))
                .contentTransition(.numericText(value: Double(step)))
                .foregroundStyle(.white)
            Text("/ \(String(format: "%02d", slides.count))")
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .font(Theme.body(12, weight: .medium))
        .tracking(1.5)
        .monospacedDigit()
        .padding(.top, 6)
    }

    /// Tappable hairline segments — the filled run grows with a spring.
    private var segments: some View {
        HStack(spacing: 6) {
            ForEach(1...slides.count, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.white.opacity(0.92) : Color.white.opacity(0.22))
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle().inset(by: -12))
                    .onTapGesture {
                        Haptics.select()
                        step = i
                    }
            }
        }
    }

    private func twoTone(first: String, accent: String) -> some View {
        (Text(first + " ").foregroundStyle(Theme.ink)
         + Text(accent).foregroundStyle(Color.white.opacity(0.62)))
            .font(Theme.headline(26, weight: .medium))
            .kerning(-0.4)
            .multilineTextAlignment(.leading)
            .lineSpacing(2)
    }
}

#Preview {
    WelcomeView().environment(AppState())
}
