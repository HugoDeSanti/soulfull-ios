//
//  OnboardingView.swift
//  Soulfull Gatherings
//
//  Container for the 4-step onboarding + finishing slide.
//  Shared shell handles backdrop, top bar (back / progress / skip), and
//  the bottom CTA. Individual step views render only the question body.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @State private var vm = OnboardingViewModel()

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
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(vm.step)
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: vm.step)
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
                    .padding(.horizontal, 22)
                    .padding(.top, 16)

                stepBody()
                    .padding(.horizontal, 22)
                    .padding(.top, 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                SGPrimaryButton(
                    title: "Next",
                    enabled: vm.canAdvance
                ) {
                    vm.next()
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if !vm.isFirstStep {
                CircleIconButton(systemName: "chevron.left", size: 36) { vm.back() }
            } else {
                Color.clear.frame(width: 36, height: 36)
            }

            // Progress bar + counter
            HStack(spacing: 14) {
                progressBar
                Text("\(vm.step.index + 1)/\(OnboardingViewModel.Step.questionCount)")
                    .font(Theme.body(13))
                    .foregroundStyle(Color.white.opacity(0.62))
                Button {
                    Haptics.tap()
                    app.finishOnboardingSkipping(name: vm.name)
                } label: {
                    Text("skip")
                        .font(Theme.body(14))
                        .foregroundStyle(Color.white.opacity(0.62))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: max(0, geo.size.width * progress))
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: progress)
            }
        }
        .frame(height: 6)
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
                .font(Theme.headline(30))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .kerning(-0.2)

            TextField("", text: $vm.name, prompt:
                Text("Your name")
                    .font(Theme.headline(20))
                    .italic()
                    .foregroundStyle(Color.white.opacity(0.45))
            )
            .focused($focused)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { vm.next() }
            .multilineTextAlignment(.center)
            .font(Theme.headline(22))
            .italic()
            .foregroundStyle(Theme.ink)
            .padding(.bottom, 6)
            .frame(maxWidth: 260)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(height: 1)
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
    @State private var breathing = false

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: "finish-bg", blur: 6, darken: 0.62)

            VStack(spacing: 0) {
                Spacer()

                Image("soulfull-logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 160, height: 160)
                    .scaleEffect(breathing ? 1.06 : 0.94)
                    .opacity(breathing ? 1 : 0.85)
                    .shadow(color: .white.opacity(0.18), radius: 24)
                    .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: breathing)

                Text("WELCOME, \(name.isEmpty ? "friend" : name.uppercased())")
                    .font(Theme.eyebrow(11))
                    .tracking(4)
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .padding(.top, 24)

                Text("\u{201C}The soul knows the way — we're simply here to walk beside you.\u{201D}")
                    .font(Theme.headline(28))
                    .italic()
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .padding(.top, 18)

                Text("Your space is ready whenever you are.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.top, 18)

                Spacer()

                SGPrimaryButton(title: "I'm ready") {
                    onEnter()
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .onAppear { breathing = true }
    }
}

// MARK: - Option card (glass tile with index + label + honey glow when selected)

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
                            .foregroundStyle(Color.white.opacity(0.62))
                            .padding(.bottom, 14)
                    }
                    Text(label)
                        .font(Theme.body(subtle ? 13 : 15))
                        .foregroundStyle(Theme.ink.opacity(subtle ? 0.85 : 1))
                        .multilineTextAlignment(subtle ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: subtle ? .center : .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: subtle ? .center : .bottomLeading)
                .padding(subtle ? 18 : 16)
            }
            .frame(minHeight: subtle ? 64 : 108)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: subtle ? 28 : 26, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.22 : 0.10))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: subtle ? 28 : 26, style: .continuous))
                    if selected && !subtle {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Theme.honey.opacity(0.55), Theme.honey.opacity(0.18), .clear],
                                    center: .center, startRadius: 6, endRadius: 90
                                )
                            )
                            .blur(radius: 8)
                            .frame(width: 220, height: 220)
                            .offset(x: 60, y: 50)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: subtle ? 28 : 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: subtle ? 28 : 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.55 : 0.20), lineWidth: 1)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tiny shared atoms used by the question-step bodies

@ViewBuilder
private func eyebrow(_ text: String) -> some View {
    Text(text)
        .font(Theme.body(12))
        .foregroundStyle(Color.white.opacity(0.62))
        .tracking(0.2)
        .padding(.horizontal, 2)
}

@ViewBuilder
private func headline(_ text: String) -> some View {
    Text(text)
        .font(Theme.headline(34))
        .foregroundStyle(Theme.ink)
        .multilineTextAlignment(.leading)
        .lineSpacing(2)
        .kerning(-0.4)
        .frame(maxWidth: 320, alignment: .leading)
}

#Preview {
    OnboardingView().environment(AppState())
}
