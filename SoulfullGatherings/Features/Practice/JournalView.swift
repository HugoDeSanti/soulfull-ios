//
//  JournalView.swift
//  Soulfull Gatherings
//
//  Journal Prompts section: a list of reflective prompts, each opening a
//  detail screen with the full prompt and a (device-local) writing area.
//  Mock-driven until a `journal_prompts` table is seeded.
//

import SwiftUI

struct JournalListView: View {
    let onOpen: (JournalPrompt) -> Void
    private let prompts = JournalPrompt.all

    var body: some View {
        PracticeListScaffold(
            title: PracticeMenuItem.journal.title,
            blurb: PracticeMenuItem.journal.blurb,
            systemImage: PracticeMenuItem.journal.systemImage,
            backdrop: PracticeMenuItem.journal.imageName
        ) {
            VStack(spacing: 10) {
                ForEach(prompts) { prompt in
                    PressableCard(action: { onOpen(prompt) }) {
                        promptRow(prompt)
                    }
                    .listReveal()
                }
            }
        }
    }

    private func promptRow(_ prompt: JournalPrompt) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "pencil.line")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.theme.uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(Theme.inkSoft)
                Text(prompt.title)
                    .font(Theme.headline(17))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.top, 14)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .soulGlassCard(radius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Detail

struct JournalDetailView: View {
    let prompt: JournalPrompt
    @State private var entry = ""
    @FocusState private var writing: Bool

    /// Reflections are private, device-local notes (per CLAUDE.md) — one entry
    /// per prompt, namespaced to the signed-in member by `LocalUserStore`.
    /// A flat `sg.journal.<id>` key was keyed to the *device*, so two people
    /// sharing a phone read each other's writing.
    private var storageKey: String { "journal.\(prompt.id)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PracticeBackBar(label: "Journal")

                // The question recedes while writing so the words take the room.
                VStack(alignment: .leading, spacing: 8) {
                    Text(prompt.theme.uppercased())
                        .font(Theme.eyebrow(11))
                        .tracking(3)
                        .foregroundStyle(Theme.inkSoft)
                        .onPhoto()
                    Text(prompt.title)
                        .font(Theme.headline(30))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.3)
                        .fixedSize(horizontal: false, vertical: true)
                        .onPhoto()

                    // Framing as a pull-quote against a honey rule.
                    HStack(alignment: .top, spacing: 14) {
                        Rectangle()
                            .fill(Theme.honey.opacity(0.65))
                            .frame(width: 2)
                        Text(prompt.prompt)
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.inkOnPhoto)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .onPhoto()
                    }
                    .padding(.top, 8)
                }
                .opacity(writing ? 0.45 : 1)
                .blur(radius: writing ? 1.5 : 0)
                .animation(.easeInOut(duration: 0.35), value: writing)

                GlassCard(radius: 18, padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR REFLECTION")
                            .font(Theme.eyebrow(10))
                            .tracking(2)
                            .foregroundStyle(.white)
                        ZStack(alignment: .topLeading) {
                            if entry.isEmpty {
                                Text("Write freely. No one but you sees this.")
                                    .font(Theme.body(15))
                                    .foregroundStyle(Theme.muted)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $entry)
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.ink)
                                .tint(Theme.honey)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 200)
                                .focused($writing)
                        }
                    }
                }

                HStack {
                    Text("Saved on this device.")
                    Spacer()
                    if !entry.isEmpty {
                        Text("\(entry.split(whereSeparator: \.isWhitespace).count) words")
                            .contentTransition(.numericText())
                            .animation(.default, value: entry.count)
                    }
                }
                .font(Theme.body(11))
                .foregroundStyle(Theme.muted)

                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background {
            PhotoBackdrop(imageName: prompt.imageUrl, blur: 26, darken: 0.82)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { entry = LocalUserStore.shared.string(forKey: storageKey) ?? "" }
        .onChange(of: entry) {
            LocalUserStore.shared.set(entry, forKey: storageKey)
        }
        // Records that this prompt was opened, and for how long — never the
        // reflection itself, which stays on the device. A prompt counts as done
        // once something has been written against it.
        .practiceActivity(.journal(prompt), completedWhen: { !entry.isEmpty })
        .toolbar {
            if writing {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { writing = false }
                            .foregroundStyle(Theme.honey)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        JournalDetailView(prompt: JournalPrompt.all[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
