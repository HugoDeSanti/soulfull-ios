//
//  OnboardingView.swift
//  Soulfull Gatherings
//
//  Container for the 4-step onboarding + finishing slide.
//  Shared shell handles backdrop, top bar (back / progress / skip), and
//  the bottom CTA. Individual step views render only the question body.
//
//  No account is asked for here — browsing is open to a guest, and the sign-in
//  prompt happens later at the first practice (see `AccountGate`).
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @State private var vm: OnboardingViewModel

    /// False for a member who signed in before onboarding — see
    /// `OnboardingViewModel.firstStep`.
    init(asksName: Bool = true) {
        _vm = State(initialValue: OnboardingViewModel(asksName: asksName))
    }

    var body: some View {
        ZStack {
            if vm.step == .finish {
                FinishStepView(name: vm.name) {
                    vm.complete(into: app)
                }
                .transition(.opacity)
            } else {
                OnboardingShell(vm: vm) {
                    Group {
                        switch vm.step {
                        case .name:      NameStep(vm: vm)
                        case .intention: IntentionStep(vm: vm)
                        case .state:     BodyStateStep(vm: vm)
                        case .frequency: FrequencyStep(vm: vm)
                        case .finish:    EmptyView()
                        }
                    }
                    // Soft (blur-free) variant, a plain crossfade: the name
                    // step's TextField is UIKit-backed and can't sit under a
                    // Metal filter pass.
                    .transition(.editorialPageSoft)
                    .id(vm.step)
                }
                .transition(.opacity)
            }
        }
        .animation(Theme.Motion.settle, value: vm.step)
        // Allow native swipe-from-edge to act as "back".
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { g in
                    if g.translation.width > 60, !vm.isFirstStep { vm.back() }
                }
        )
    }
}

// MARK: - Shell

private struct OnboardingShell<StepBody: View>: View {
    @Environment(AppState.self) private var app
    let vm: OnboardingViewModel
    let stepBody: () -> StepBody

    init(vm: OnboardingViewModel, @ViewBuilder content: @escaping () -> StepBody) {
        self.vm = vm
        self.stepBody = content
    }

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: "onb-bg", blur: 6, darken: 0.62)

            VStack(spacing: 0) {
                topBar
                    // The back glyph's 44pt square centres it on the gutter.
                    .padding(.leading, Theme.gutter - 13)
                    .padding(.trailing, Theme.gutter)
                    .padding(.top, 10)

                stepBody()
                    .padding(.horizontal, Theme.gutter - 8)
                    .padding(.top, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                SGPrimaryButton(
                    title: "Next",
                    enabled: vm.canAdvance
                ) {
                    vm.next()
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 28)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if !vm.isFirstStep {
                GlyphButton(systemName: "arrow.left") { vm.back() }
                    .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            // Progress bar + counter
            HStack(spacing: 14) {
                progressBar
                Text("\(vm.step.index + 1)/\(OnboardingViewModel.Step.questionCount)")
                    .font(Theme.body(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkOnPhoto)
                Button {
                    Haptics.tap()
                    app.finishOnboardingSkipping(name: vm.nameAnswer)
                } label: {
                    Text("skip")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.inkOnPhoto)
                        // A 44pt target around a 14pt word without moving it:
                        // the padding grows the hit area, and the negative
                        // padding hands the room back so the bar keeps its
                        // height. Plain buttons answer only where they draw
                        // (gotcha #5).
                        .padding(.vertical, 14)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                        .padding(.vertical, -14)
                        .padding(.horizontal, -10)
                }
                .buttonStyle(.plain)
            }
            .onPhoto()
        }
    }

    private var progressBar: some View {
        // A hairline track with an ink run along it, eased from step to
        // step. The run is a leading-anchored scale fill — no GeometryReader,
        // so the bar can never over-claim width inside the HStack.
        Rectangle()
            .fill(Theme.ink.opacity(0.18))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.ink)
                    .scaleEffect(x: progress, y: 1, anchor: .leading)
                    .animation(Theme.Motion.settle, value: progress)
            }
            .clipped()
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private var progress: CGFloat {
        CGFloat(vm.step.index + 1) / CGFloat(OnboardingViewModel.Step.questionCount)
    }
}

// MARK: - Step bodies

private struct NameStep: View {
    @Bindable var vm: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Text("What should we call you?")
                .font(Theme.headline(30, weight: .light))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .kerning(-0.5)
                // The question only: never the TextField underneath it.
                .onPhoto()

            TextField("", text: $vm.name, prompt:
                Text("Your name")
                    .font(Theme.headline(20))
                    .italic()
                    .foregroundStyle(Theme.ink.opacity(0.45))
            )
            .focused($focused)
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { vm.next() }
            // The title is empty (the prompt does the visual work), which left
            // VoiceOver nothing to call the field once it had text in it.
            .accessibilityLabel("Your name")
            .accessibilityIdentifier("onboarding-name")
            .multilineTextAlignment(.center)
            .font(Theme.headline(22))
            .italic()
            .foregroundStyle(Theme.ink)
            .padding(.bottom, 6)
            .frame(maxWidth: 260)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.ink.opacity(focused ? 0.85 : 0.35))
                    .frame(height: 1)
                    .animation(Theme.Motion.settle, value: focused)
            }
            Spacer()
            Spacer()
        }
        .onAppear { focused = true }
    }
}

private struct IntentionStep: View {
    let vm: OnboardingViewModel
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]

    var body: some View {
        let mainOpts = IntentionOption.all.filter { !$0.isSubtle }
        let subtleOpts = IntentionOption.all.filter { $0.isSubtle }

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                eyebrow("Select all that apply")
                headline(vm.name.isEmpty
                         ? "what's calling you here?"
                         : "\(vm.name), what's calling you here?")

                VStack(spacing: 12) {
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(Array(mainOpts.enumerated()), id: \.element.id) { idx, opt in
                            OptionCard(
                                index: idx + 1,
                                label: opt.label,
                                selected: vm.intentions.contains(opt.id),
                                subtle: false
                            ) { vm.toggleIntention(opt.id) }
                        }
                    }
                    ForEach(subtleOpts) { opt in
                        OptionCard(
                            index: nil,
                            label: opt.label,
                            selected: vm.intentions.contains(opt.id),
                            subtle: true
                        ) { vm.toggleIntention(opt.id) }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .clipped()
    }
}

private struct BodyStateStep: View {
    let vm: OnboardingViewModel
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]

    var body: some View {
        let mainOpts = BodyStateOption.all.filter { !$0.isSubtle }
        let subtleOpts = BodyStateOption.all.filter { $0.isSubtle }

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                eyebrow("Choose one")
                headline("how is your nervous system today?")

                VStack(spacing: 12) {
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(Array(mainOpts.enumerated()), id: \.element.id) { idx, opt in
                            OptionCard(
                                index: idx + 1,
                                label: opt.label,
                                selected: vm.bodyState == opt.id,
                                subtle: false
                            ) { vm.pickState(opt.id) }
                        }
                    }
                    ForEach(subtleOpts) { opt in
                        OptionCard(
                            index: nil,
                            label: opt.label,
                            selected: vm.bodyState == opt.id,
                            subtle: true
                        ) { vm.pickState(opt.id) }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .clipped()
    }
}

private struct FrequencyStep: View {
    let vm: OnboardingViewModel
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                eyebrow("Choose one")
                headline("and, what rhythm feels right?")

                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(Array(FrequencyOption.all.enumerated()), id: \.element.id) { idx, opt in
                        OptionCard(
                            index: idx + 1,
                            label: opt.label,
                            selected: vm.frequency == opt.id,
                            subtle: false
                        ) { vm.pickFrequency(opt.id) }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .clipped()
    }
}

// MARK: - Finish

private struct FinishStepView: View {
    let name: String
    let onEnter: () -> Void

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: "finish-bg", blur: 6, darken: 0.62)

            VStack(spacing: 0) {
                Spacer()

                Image("soulfull-logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 140, height: 140)
                    .breathing(scale: 0.985...1.015, opacity: 0.8...1.0)
                    // Decorative: the welcome line under it does the talking.
                    .accessibilityHidden(true)

                Text("WELCOME, \(name.isEmpty ? "friend" : name.uppercased())")
                    .font(Theme.eyebrow(11))
                    .tracking(4)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 36)
                    .onPhoto()

                Text("\u{201C}The soul knows the way — we're simply here to walk beside you.\u{201D}")
                    .font(Theme.headline(28, weight: .light))
                    .italic()
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .padding(.top, 20)
                    .onPhoto()

                Text("Your space is ready whenever you are.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.top, 18)
                    .onPhoto()

                Spacer()

                SGPrimaryButton(title: "I'm ready") {
                    onEnter()
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Option card (square veiled tile: index + label; chosen = ink hairline)

private struct OptionCard: View {
    let index: Int?
    let label: String
    let selected: Bool
    let subtle: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: subtle ? .center : .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    if let idx = index {
                        Text(String(format: "%02d", idx))
                            .font(Theme.body(11))
                            .tracking(1.2)
                            .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
                            .padding(.bottom, 14)
                    }
                    Text(label)
                        .font(Theme.body(subtle ? 13 : 15, weight: selected ? .medium : .regular))
                        .foregroundStyle(Theme.ink.opacity(subtle ? 0.85 : 1))
                        .multilineTextAlignment(subtle ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: subtle ? .center : .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: subtle ? .center : .bottomLeading)
                .padding(subtle ? 18 : 16)
            }
            .frame(minHeight: subtle ? 64 : 108)
            // Chosen: the hairline turns to ink and the surface lifts a
            // shade. Nothing glows, grows or glints — it settles.
            .soulGlassCard(tint: selected ? Theme.ink.opacity(0.07) : nil,
                           stroke: selected ? Theme.ink.opacity(0.75) : Theme.glassBorderHigh)
            .animation(Theme.Motion.settle, value: selected)
        }
        .buttonStyle(.soulPressableQuiet)
        // A choice shows only as a change of line and numeral, which
        // VoiceOver can't see: say "selected" out loud.
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("onboarding-option")
    }
}

// MARK: - Tiny shared atoms used by the question-step bodies

@ViewBuilder @MainActor
private func eyebrow(_ text: String) -> some View {
    Text(text)
        .font(Theme.body(12))
        .foregroundStyle(Theme.inkOnPhoto)
        .tracking(0.2)
        .padding(.horizontal, 2)
        .onPhoto()
}

@ViewBuilder @MainActor
private func headline(_ text: String) -> some View {
    Text(text)
        .font(Theme.headline(34, weight: .light))
        .foregroundStyle(Theme.ink)
        .multilineTextAlignment(.leading)
        .lineSpacing(2)
        .kerning(-0.7)
        .frame(maxWidth: 320, alignment: .leading)
        .onPhoto()
}

#Preview {
    OnboardingView().environment(AppState())
}
