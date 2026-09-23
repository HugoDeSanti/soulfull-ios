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
                // A count and never faces: the server sends none for a
                // journal prompt, whose title can say what someone is
                // working through.
                PresenceLine(kind: .journal, contentID: prompt.id)
                    .padding(.top, 2)
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
    /// Debounces the save so a long reflection isn't rewritten per keystroke.
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var writing: Bool
    /// A tap on the receded question brings it back mid-sentence, without
    /// touching the keyboard. Reset on every new sitting and as soon as
    /// writing resumes, so the default is always "the words take the room".
    @State private var peeking = false

    /// Reflections are private, device-local notes (per CLAUDE.md) — one entry
    /// per prompt, namespaced to the signed-in member by `LocalUserStore`.
    /// A flat `sg.journal.<id>` key was keyed to the *device*, so two people
    /// sharing a phone read each other's writing.
    private var storageKey: String { "journal.\(prompt.id)" }

    /// The question is out of the way only while writing *and* not being
    /// peeked at — one value so the fade animates the same whichever of the
    /// two changed.
    private var receded: Bool { writing && !peeking }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PracticeBackBar(label: "Journal")

                // The question recedes while writing so the words take the
                // room — but it stays one tap away. Forgetting what you were
                // answering used to mean dismissing the keyboard to re-read it.
                Button { peeking.toggle() } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        promptBlock
                            .opacity(receded ? 0.45 : 1)
                            .blur(radius: receded ? 1.5 : 0)
                        if writing {
                            // Held in the layout through a peek: if the hint
                            // left, revealing the question would shunt the
                            // editor — and the cursor — down under the reader.
                            peekHint
                                .opacity(receded ? 1 : 0)
                                .accessibilityHidden(!receded)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Gotcha #5: text hit-tests its glyphs, so the gaps between
                    // these lines would be dead without a shape to fill them.
                    .contentShape(Rectangle())
                }
                .buttonStyle(SoulPressableStyle(scale: 0.99, dim: false))
                .disabled(!writing)
                .accessibilityHint("Brings the prompt back while you write")
                .animation(.easeInOut(duration: 0.35), value: receded)

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
        .onAppear { entry = LocalUserStore.shared.privateText(forKey: storageKey) ?? "" }
        // A peek belongs to one sitting: tapping back into the editor starts
        // receded again rather than inheriting the last reveal.
        .onChange(of: writing) { _, isWriting in
            if isWriting { peeking = false }
        }
        // Debounced: this wrote the whole entry on every keystroke, which for a
        // long reflection is a plist/file write per character.
        .onChange(of: entry) {
            // Typing again puts the question back where it was.
            peeking = false
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                LocalUserStore.shared.setPrivateText(entry, forKey: storageKey)
            }
        }
        .onDisappear {
            saveTask?.cancel()
            LocalUserStore.shared.setPrivateText(entry, forKey: storageKey)
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

    /// The question itself — eyebrow, title, and the prompt as a pull-quote
    /// against a honey rule.
    private var promptBlock: some View {
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

            PresenceLine(kind: .journal, contentID: prompt.id)
                .padding(.top, 6)
                .onPhoto()
        }
    }

    /// Says the receded question can be tapped. It sits *outside* the blur —
    /// a hint you have to defocus to read would be no hint at all.
    private var peekHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.system(size: 9, weight: .semibold))
            Text("TAP TO RE-READ")
                .font(Theme.eyebrow(9))
                .tracking(2)
        }
        .foregroundStyle(Theme.inkSoft)
        .onPhoto()
        .padding(.top, 10)
        .transition(.opacity)
    }
}

#Preview {
    NavigationStack {
        JournalDetailView(prompt: JournalPrompt.all[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
