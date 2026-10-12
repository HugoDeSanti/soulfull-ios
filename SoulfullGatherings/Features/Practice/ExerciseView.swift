//
//  ExerciseView.swift
//  Soulfull Gatherings
//
//  Movement section: guided exercise sequences. The list shows each routine;
//  the detail screen lays out its numbered steps with sets/reps, and ends with
//  what members have said about it.
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
                VStack(spacing: 0) {
                    ForEach(store.library.exercises) { exercise in
                        PressableCard(action: { onOpen(exercise) }) {
                            exerciseRow(exercise)
                        }
                        .listReveal()
                    }
                    PracticeRule()
                }
            }
        }
        .task { await store.refresh() }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 16) {
            CatalogImage(exercise.imageUrl) { $0.resizable().scaledToFill() }
                .frame(width: 56, height: 56)
                .clipped()
                .overlay(Rectangle().strokeBorder(Theme.glassBorder, lineWidth: Theme.hairline))

            VStack(alignment: .leading, spacing: 6) {
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
            // The row lies open on the section's photograph.
            .onPhoto()
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { PracticeRule() }
        .contentShape(Rectangle())
    }
}

// MARK: - Detail

struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PracticeBackBar(label: "Movement")

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(exercise.focus.uppercased())
                        Text("·")
                        Text(exercise.durationLabel.uppercased())
                    }
                    .font(Theme.eyebrow(11))
                    .tracking(2)
                    .foregroundStyle(Theme.inkSoft)

                    Text(exercise.title)
                        .font(Theme.headline(32, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.7)
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

                GuideCard(instructorID: exercise.instructorID, from: exercise.title)

                // The steps set open under a caps label, divided by hairlines.
                VStack(alignment: .leading, spacing: 0) {
                    Text("THE SEQUENCE")
                        .font(Theme.eyebrow(11))
                        .tracking(3)
                        .foregroundStyle(Theme.inkSoft)
                        .onPhoto()
                        .padding(.bottom, 16)
                    ForEach(Array(exercise.steps.enumerated()), id: \.element.id) { index, step in
                        // Open on the photograph now, not inside a glass box.
                        NumberedStepRow(index: index + 1, title: step.name, detail: step.detail)
                            .onPhoto()
                            .padding(.vertical, 16)
                            .overlay(alignment: .top) { PracticeRule() }
                    }
                    PracticeRule()
                }
                .padding(.top, 20)

                // A section's gap below the sequence (the stack adds 28).
                PracticeCommentsSection(thread: CommentThread(exercise))
                    .padding(.top, Theme.sectionGap - 28)

                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .statusBarFade()
        .practiceActivity(.exercise(exercise))
        .background {
            PhotoBackdrop(imageName: exercise.imageUrl, blur: 24, darken: 0.8)
        }
    }
}

// Its sample content (`Fixtures.swift`) exists only in DEBUG.
#if DEBUG
#Preview {
    NavigationStack {
        ExerciseDetailView(exercise: Exercise.mock[0])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
#endif
