//
//  WelcomeView.swift
//  Soulfull Gatherings
//
//  Splash (the logo breathing in light over the tropical backdrop) → the
//  explainer slides. The backdrop pans like a slow camera move as slides
//  advance; copy comes into focus where it stands; a folio counter +
//  hairline segments replace dots. Under Reduce Motion the camera holds
//  still and copy simply fades.
//
//  "I already have an account" offers a sign-in sheet. Closing it leaves
//  them here, free to Begin as a guest: it is an offer, not a gate.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 = splash, 1...3 = explainer slides.
    @State private var step: Int = 0
    @State private var showSignIn = false

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
              body: "Luxurious in-person gatherings and self-paced digital retreats — breathwork, meditation, somatic exercises, movement, and nourishing food."),
        Slide(id: "community",
              eyebrow: "A Conscious Community",
              firstHalf: "A worldwide community",
              accentHalf: "that travels, heals, and connects.",
              body: "A conscious space for shared practice — see what the circle is practicing, and practice alongside friends."),
    ]
    // A third slide sold "Soul AI — Meet Soul, your companion through the
    // journey". There is no AI in this app and none planned, and this ran on
    // every first launch, so it promised every new user a feature that does not
    // exist. Everything here is driven off `slides.count`, so removing it needs
    // no other change. Don't re-add a slide for something unbuilt.

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: "welcome-bg", blur: 6, darken: 0.62,
                          pan: CGFloat(step) / CGFloat(max(slides.count, 1)))

            if step == 0 {
                splash
                    .transition(rise)
            } else {
                slideStack
                    .transition(rise)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if step == 0 {
                Haptics.tap()
                step = 1
            }
        }
        .animation(reduceMotion ? Theme.Motion.settle : Theme.Motion.stage, value: step)
        .sheet(isPresented: $showSignIn, onDismiss: { app.returnFromWelcomeSignIn() }) {
            AccountView(mode: .signIn)
        }
    }

    /// The focus-pull and the paired page handoff, or a plain fade under
    /// Reduce Motion, which drops the blur as well.
    private var rise: AnyTransition { reduceMotion ? .opacity : .editorialRise }
    private var page: AnyTransition { reduceMotion ? .opacity : .editorialPage }

    // MARK: - Splash

    private var splash: some View {
        ZStack {
            // Wordmark — alone, with the photograph and space around it. It
            // breathes in light; its size barely moves.
            Image("soulfull-logo-white")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .breathing(scale: 0.985...1.015, opacity: 0.8...1.0)
                .accessibilityLabel("Soulfull")

            VStack {
                Spacer()
                Text("TAP TO CONTINUE")
                    .font(Theme.eyebrow(11))
                    .tracking(3.4)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(14)
                    .onPhoto()
                    .breathing(scale: 1.0...1.0, opacity: 0.4...0.9)
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
                    // The splash already named it; here it's the masthead.
                    .accessibilityHidden(true)
                Spacer()
                folio
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 24)

            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                Text(slide.eyebrow.uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)

                twoTone(first: slide.firstHalf, accent: slide.accentHalf)

                Text(slide.body)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(3)
            }
            .padding(.horizontal, Theme.gutter)
            .onPhoto()
            .id(slide.id)
            .transition(page)

            // Hairline progress segments
            segments
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 36)

            VStack(spacing: 4) {
                SGPrimaryButton(title: isLast ? "Begin" : "Next") {
                    if isLast {
                        app.beginOnboarding()
                    } else {
                        step += 1
                    }
                }
                if isLast {
                    // Offers sign-in. This used to call `beginOnboarding()`,
                    // exactly like Begin, so a returning member answered four
                    // questions and landed as a guest. Where a sign-in leads
                    // is `AppState.returnFromWelcomeSignIn()`.
                    Button {
                        Haptics.tap()
                        showSignIn = true
                    } label: {
                        Text("I already have an account")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 12)
                            // 44pt tall, and tappable between the letters
                            // (gotcha #5).
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.soulPressableQuiet)
                    .transition(rise)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 28)
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

    /// Magazine folio — "02 / 03", the current number crossfading.
    private var folio: some View {
        HStack(spacing: 3) {
            Text(String(format: "%02d", step))
                .contentTransition(.opacity)
                .foregroundStyle(Theme.ink)
            Text("/ \(String(format: "%02d", slides.count))")
                .foregroundStyle(Theme.ink.opacity(0.5))
        }
        .font(Theme.body(12, weight: .medium))
        .tracking(1.5)
        .monospacedDigit()
        .padding(.top, 6)
    }

    /// Tappable hairline segments — the filled run lights with the step's ease.
    private var segments: some View {
        HStack(spacing: 6) {
            ForEach(1...slides.count, id: \.self) { i in
                Rectangle()
                    .fill(i <= step ? Theme.ink.opacity(0.92) : Theme.ink.opacity(0.22))
                    .frame(height: 1)
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
         + Text(accent).foregroundStyle(Theme.ink.opacity(0.62)))
            .font(Theme.headline(30, weight: .light))
            .kerning(-0.6)
            .multilineTextAlignment(.leading)
            .lineSpacing(2)
    }
}

#Preview {
    let app = AppState()
    // The sign-in sheet reads both.
    return WelcomeView()
        .environment(app)
        .environment(app.auth)
        .environment(app.settings)
}
