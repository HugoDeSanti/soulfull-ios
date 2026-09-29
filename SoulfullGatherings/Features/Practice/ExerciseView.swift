//
//  ExerciseView.swift
//  Soulfull Gatherings
//
//  Movement section: guided exercise sequences. The list shows each routine;
//  the detail screen lays out its numbered steps with sets/reps.
//  The sequences are the `exercises` table, through WrittenPracticeStore.
//

import SwiftUI

struct ExerciseListView: View {
    let onOpen: (Exercise) -> Void
    private let store = WrittenPracticeStore.shared

    var body: some View {
        PracticeListScaffold(
            title: PracticeMenuItem.movement.title,
            blurb: PracticeMenuItem.movement.blurb,
            systemImage: PracticeMenuItem.movement.systemImage,
            backdrop: PracticeMenuItem.movement.imageName
        ) {
            if store.library.exercises.isEmpty {
                WrittenLibraryPlaceholder(item: .movement, noun: "sequences")
            } else {
                VStack(spacing: 10) {
                    ForEach(store.library.exercises) { exercise in
                        PressableCard(action: { onOpen(exercise) }) {
                            exerciseRow(exercise)
                        }
                        .listReveal()
                    }
                }
            }
        }
        .task { await store.refresh() }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 14) {
            CatalogImage(exercise.imageUrl) { $0.resizable().scaledToFill() }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.title)
                    .font(Theme.headline(17))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(exercise.focus)
                    Text("·")
                    Text(exercise.durationLabel)
                    Text("·")
                    Text("\(exercise.steps.count) moves")
                }
                .font(Theme.eyebrow(10))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkSoft)
                PresenceLine(kind: .exercise, contentID: exercise.id, faceSize: 18)
                    .padding(.top, 4)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .soulGlassCard(radius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Detail

struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PracticeBackBar(label: "Movement")

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(exercise.focus.uppercased())
                        Text("·")
                        Text(exercise.durationLabel.uppercased())
                    }
                    .font(Theme.eyebrow(11))
                    .tracking(2)
                    .foregroundStyle(Theme.inkSoft)

                    Text(exercise.title)
                        .font(Theme.headline(32))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(exercise.blurb)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.inkOnPhoto)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    PresenceLine(kind: .exercise, contentID: exercise.id, faceSize: 22)
                        .padding(.top, 6)
                }
                // Header block over the (blurred) photo backdrop.
                .onPhoto()

                // Glass, so outside the header's halo.
                GuideCard(kind: .exercise, contentID: exercise.id, from: exercise.title)

                Text("THE SEQUENCE")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 4)
                    .onPhoto()

                VStack(spacing: 14) {
                    ForEach(Array(exercise.steps.enumerated()), id: \.element.id) { index, step in
                        NumberedStepRow(index: index + 1, title: step.name, detail: step.detail)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))

                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .practiceActivity(.exercise(exercise))
        .background {
            PhotoBackdrop(imageName: exercise.imageUrl, blur: 24, darken: 0.8)
        }
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView(exercise: Exercise.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
