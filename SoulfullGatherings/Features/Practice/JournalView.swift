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
                    promptRow(prompt)
                        .onTapGesture {
                            Haptics.tap()
                            onOpen(prompt)
                        }
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Detail

struct JournalDetailView: View {
    let prompt: JournalPrompt
    @State private var entry = ""
    @FocusState private var writing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PracticeBackBar(label: "Journal")

                VStack(alignment: .leading, spacing: 8) {
                    Text(prompt.theme.uppercased())
                        .font(Theme.eyebrow(11))
                        .tracking(3)
                        .foregroundStyle(Theme.muted)
                    Text(prompt.title)
                        .font(Theme.headline(30))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(prompt.prompt)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

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

                Text("Saved only on this device for now.")
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
