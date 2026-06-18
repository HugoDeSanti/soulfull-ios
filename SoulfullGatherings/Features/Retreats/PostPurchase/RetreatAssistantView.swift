//
//  RetreatAssistantView.swift
//  Soulfull Gatherings
//
//  Pre-retreat concierge chat — dark, all-Geist translation of the Claude
//  Design `mallorca-chatbot` brochure card. Replies are mocked locally (see
//  RetreatAssistantViewModel); there is no backend. Keep Metal/shader effects
//  off this screen — the composer is a UIKit-backed TextField (CLAUDE.md
//  rendering gotcha #1), so its background is a plain fill, not glass.
//

import SwiftUI

struct RetreatAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    let retreat: Retreat

    @State private var vm: RetreatAssistantViewModel
    @State private var input = ""
    @FocusState private var focused: Bool

    init(retreat: Retreat) {
        self.retreat = retreat
        let exp = retreat.experience ?? RetreatExperience.curated(for: retreat)
        _vm = State(initialValue: RetreatAssistantViewModel(post: exp?.postBooking))
    }

    var body: some View {
        ZStack {
            RetreatPalette.espresso.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                messagesScroll
                if vm.showSuggestions && !vm.suggestions.isEmpty { suggestionChips }
                composer
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap(); dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(RetreatPalette.cream)
                    .frame(width: 36, height: 36)
                    .soulGlass(in: Circle(), tint: RetreatPalette.glassTint, interactive: true, stroke: RetreatPalette.glassLine)
            }
            .buttonStyle(.soulPressableChip)

            Image("soulfull-logo-white")
                .resizable().scaledToFit().frame(width: 22, height: 22)
                .frame(width: 42, height: 42)
                .background(RetreatPalette.olive, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Soulfull Gatherings")
                    .font(Theme.headline(18, weight: .medium)).foregroundStyle(RetreatPalette.cream)
                HStack(spacing: 6) {
                    Circle().fill(RetreatPalette.olive).frame(width: 6, height: 6).pulse()
                    Text("Concierge · replies instantly")
                        .font(Theme.body(11)).foregroundStyle(RetreatPalette.creamSoft)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 14)
        .background(RetreatPalette.espresso)
        .overlay(alignment: .bottom) { Rectangle().fill(RetreatPalette.glassLine).frame(height: 1) }
    }

    // MARK: - Messages

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your \(retreat.name) retreat assistant — ask anything before you go")
                        .font(Theme.body(11)).foregroundStyle(RetreatPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)

                    ForEach(vm.messages) { message in
                        bubble(message).id(message.id)
                    }

                    if vm.isTyping {
                        HStack {
                            TypingDots()
                                .padding(.horizontal, 16).padding(.vertical, 15)
                                .soulGlassCard(radius: 16, tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
                            Spacer(minLength: 40)
                        }
                        .id("typing")
                    }
                }
                .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { scrollToBottom(proxy) }
            .onChange(of: vm.isTyping) { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if vm.isTyping {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = vm.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func bubble(_ message: RetreatAssistantViewModel.Message) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(Theme.body(14)).lineSpacing(2)
                .foregroundStyle(message.role == .user ? RetreatPalette.espresso : RetreatPalette.cream)
                .padding(.horizontal, 15).padding(.vertical, 12)
                .background {
                    if message.role == .user {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(RetreatPalette.terracotta)
                    }
                }
                .modifier(BotGlass(isBot: message.role == .bot))
                .frame(maxWidth: 272, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .bot { Spacer(minLength: 40) }
        }
    }

    // MARK: - Suggestions

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.suggestions, id: \.self) { suggestion in
                    Button {
                        Haptics.tap(); vm.send(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(Theme.body(12)).foregroundStyle(RetreatPalette.creamSoft)
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .soulGlassCapsule(tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
                    }
                    .buttonStyle(.soulPressableChip)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message Soulfull Gatherings…", text: $input, axis: .vertical)
                .font(Theme.body(14)).foregroundStyle(RetreatPalette.cream)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(
                    Capsule().fill(RetreatPalette.espresso2)
                        .overlay(Capsule().strokeBorder(RetreatPalette.glassLine, lineWidth: 1))
                )

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(RetreatPalette.espresso)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(RetreatPalette.terracotta))
            }
            .buttonStyle(SoulPressableStyle(scale: 0.92, hapticOnPress: false, dim: false))
            .disabled(sendDisabled)
            .opacity(sendDisabled ? 0.4 : 1)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        .background(RetreatPalette.espresso)
        .overlay(alignment: .top) { Rectangle().fill(RetreatPalette.glassLine).frame(height: 1) }
    }

    private var sendDisabled: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isTyping
    }

    private func send() {
        let text = input
        input = ""
        vm.send(text)
    }
}

// MARK: - Bot bubble glass (applied only to bot messages)

private struct BotGlass: ViewModifier {
    let isBot: Bool
    func body(content: Content) -> some View {
        if isBot {
            content.soulGlassCard(radius: 16, tint: RetreatPalette.glassTint, stroke: RetreatPalette.glassLine)
        } else {
            content
        }
    }
}

// MARK: - Typing indicator (three bobbing dots)

private struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(RetreatPalette.muted)
                    .frame(width: 7, height: 7)
                    .scaleEffect(reduceMotion ? 1 : (animating ? 1 : 0.5))
                    .opacity(reduceMotion ? 0.8 : (animating ? 1 : 0.4))
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

#Preview {
    NavigationStack {
        RetreatAssistantView(retreat: Retreat.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
