//
//  WelcomeView.swift
//  Soulfull Gatherings
//
//  Splash (logo breathing on olive) → 3 explainer slides over a blurred
//  tropical backdrop → "Begin" routes into onboarding.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var app

    /// 0 = splash, 1...3 = explainer slides.
    @State private var step: Int = 0
    @State private var splashBreathing = false

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
            if step == 0 {
                splash
                    .transition(.opacity)
            } else {
                slideStack
                    .transition(.opacity)
            }
        }
        .background {
            PhotoBackdrop(imageName: "welcome-bg", blur: 6, darken: 0.62)
        }
        .animation(.easeInOut(duration: 0.4), value: step)
        .onAppear {
            // Auto-advance from splash after one breath cycle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
                if step == 0 { step = 1 }
            }
            splashBreathing = true
        }
    }

    // MARK: - Splash

    private var splash: some View {
        ZStack {
            // Halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.96).opacity(0.22), .clear],
                        center: .center, startRadius: 30, endRadius: 280
                    )
                )
                .frame(width: 520, height: 520)
                .scaleEffect(splashBreathing ? 1.25 : 0.85)
                .opacity(splashBreathing ? 0.6 : 0.3)
                .animation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true), value: splashBreathing)
                .blur(radius: 24)

            // Wordmark
            Image("soulfull-logo-white")
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .scaleEffect(splashBreathing ? 1.08 : 0.92)
                .opacity(splashBreathing ? 1 : 0.82)
                .animation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true), value: splashBreathing)

            VStack {
                Spacer()
                Button {
                    Haptics.tap()
                    step = 1
                } label: {
                    Text("TAP TO CONTINUE")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(3.4)
                        .foregroundStyle(Color(white: 0.92).opacity(0.62))
                        .padding(14)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 32)
                .opacity(splashBreathing ? 1 : 0)
                .animation(.easeOut(duration: 1).delay(1.0), value: splashBreathing)
            }
        }
    }

    // MARK: - Slides

    private var slideStack: some View {
        let isLast = step == slides.count
        let slide = slides[step - 1]

        return VStack(alignment: .leading, spacing: 0) {
            // Top bar
            HStack {
                Image("soulfull-logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 56, height: 56)
                    .opacity(0.88)
                Spacer()
                if !isLast {
                    Button {
                        Haptics.tap()
                        app.beginOnboarding()
                    } label: {
                        Text("SKIP")
                            .font(.system(size: 12))
                            .tracking(2)
                            .foregroundStyle(Color.white.opacity(0.6))
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                Text(slide.eyebrow.uppercased())
                    .font(.system(size: 9))
                    .tracking(3)
                    .foregroundStyle(Color(white: 0.95).opacity(0.7))

                twoTone(first: slide.firstHalf, accent: slide.accentHalf)

                Text(slide.body)
                    .font(Theme.body(13))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineSpacing(3)

                // Dots
                HStack(spacing: 8) {
                    ForEach(0..<slides.count, id: \.self) { i in
                        Capsule()
                            .fill(i + 1 == step ? Color.white : Color.white.opacity(0.24))
                            .frame(width: i + 1 == step ? 26 : 8, height: 8)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: step)
                            .onTapGesture {
                                Haptics.select()
                                step = i + 1
                            }
                    }
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 30)
            .id(slide.id)
            .transition(.opacity)

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
                        Haptics.tap()
                        app.beginOnboarding()
                    } label: {
                        Text("I already have an account")
                            .font(Theme.body(13))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 32)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
