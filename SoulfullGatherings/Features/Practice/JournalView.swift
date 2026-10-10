//
//  JournalView.swift
//  Soulfull Gatherings
//
//  Journal Prompts section: a list of reflective prompts, each opening a
//  detail screen with the full prompt and a (device-local) writing area.
//  The prompts are the `journal_prompts` table, through WrittenPracticeStore.
//

import SwiftUI

struct JournalListView: View {
    let onOpen: (JournalPrompt) -> Void
    private let store = WrittenPracticeStore.shared

    var body: some View {
        PracticeListScaffold(
            title: PracticeMenuItem.journal.title,
            blurb: PracticeMenuItem.journal.blurb,
            systemImage: PracticeMenuItem.journal.systemImage,
            backdrop: PracticeMenuItem.journal.imageName
        ) {
            if store.library.journals.isEmpty {
                WrittenLibraryPlaceholder(item: .journal, noun: "prompts")
            } else {
                VStack(spacing: 0) {
                    ForEach(store.library.journals) { prompt in
                        PressableCard(action: { onOpen(prompt) }) {
                            promptRow(prompt)
                        }
                        .listReveal()
                    }
                    PracticeRule()
                }
            }
        }
        .task { await store.refresh() }
    }

    private func promptRow(_ prompt: JournalPrompt) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "pencil.line")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
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
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 14)
        }
        // The row lies open on the section's photograph.
        .onPhoto()
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { PracticeRule() }
        .contentShape(Rectangle())
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
            VStack(alignment: .leading, spacing: 28) {
                PracticeBackBar(label: "Journal")

                // The question recedes while writing so the words take the
                // room — but it stays one tap away. Forgetting what you were
                // answering used to mean dismissing the keyboard to re-read it.
                Button { if writing { peeking.toggle() } } label: {
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
                .buttonStyle(SoulPressableStyle(dim: false))
                // A button only while writing. Out of the editor the block is
                // just the question: `.disabled` made VoiceOver read it as
                // "dimmed, button" with a hint about writing, so touches are
                // turned off instead and the button's traits go with them.
                .allowsHitTesting(writing)
                .accessibilityRemoveTraits(writing ? [] : .isButton)
                .accessibilityHint(writing ? "Brings the prompt back while you write" : "")
                .animation(Theme.Motion.settle, value: receded)

                GlassCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("YOUR REFLECTION")
                            .font(Theme.eyebrow(10))
                            .tracking(2)
                            .foregroundStyle(Theme.ink)
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
                                .tint(Theme.ember)
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
                            .animation(Theme.Motion.settle, value: entry.count)
                    }
                }
                .font(Theme.body(11))
                .foregroundStyle(Theme.inkSoft)
                .onPhoto()

                // At the foot, not above the editor: the page is for writing,
                // and a card between the question and the words would push
                // the editor down every time the question comes back.
                GuideCard(instructorID: prompt.instructorID, from: "Journal prompt")
                    .padding(.top, 24)

                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .statusBarScrim()
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
                            .foregroundStyle(Theme.ember)
                    }
                }
            }
        }
    }

    /// The question itself — eyebrow, title, and the prompt as a pull-quote
    /// against a thin ember rule.
    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Laid on the prompt's photograph: each line carries its own
            // ground (the rule stays clean).
            Text(prompt.theme.uppercased())
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
                .onPhoto()
            Text(prompt.title)
                .font(Theme.headline(30, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .onPhoto()

            HStack(alignment: .top, spacing: 16) {
                Rectangle()
                    .fill(Theme.ember.opacity(0.7))
                    .frame(width: 1)
                Text(prompt.prompt)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .onPhoto()
            }
            .padding(.top, 12)

            PresenceLine(kind: .journal, contentID: prompt.id)
                .padding(.top, 8)
                .onPhoto()
        }
    }

    /// Says the receded question can be tapped. It sits *outside* the blur —
    /// a hint you have to defocus to read would be no hint at all.
    private var peekHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.system(size: 9, weight: .regular))
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
        JournalDetailView(prompt: JournalPrompt.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
