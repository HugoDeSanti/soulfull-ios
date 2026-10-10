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
            systemImage: PracticeMenuItem.movement.systemImage
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
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(Theme.muted)
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

                // The sequence's photograph, as a square-cut plate at the head
                // of the page — it used to be blurred into the page's tint.
                Color.clear
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .overlay { CatalogImage(exercise.imageUrl) { $0.resizable().scaledToFill() } }
                    .clipped()
                    // `clipped()` clips the drawing, not the hit area: the
                    // filled photo's overflow lay over the back bar above and
                    // swallowed its taps. The plate is only a picture.
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

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
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    PresenceLine(kind: .exercise, contentID: exercise.id, faceSize: 22)
                        .padding(.top, 6)
                }

                GuideCard(instructorID: exercise.instructorID, from: exercise.title)

                // The steps set open under a caps label, divided by hairlines.
                VStack(alignment: .leading, spacing: 0) {
                    Text("THE SEQUENCE")
                        .font(Theme.eyebrow(11))
                        .tracking(3)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.bottom, 16)
                    ForEach(Array(exercise.steps.enumerated()), id: \.element.id) { index, step in
                        NumberedStepRow(index: index + 1, title: step.name, detail: step.detail)
                            .padding(.vertical, 16)
                            .overlay(alignment: .top) { PracticeRule() }
                    }
                    PracticeRule()
                }
                .padding(.top, 20)

                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .statusBarScrim()
        .practiceActivity(.exercise(exercise))
        .background {
            Atmosphere(tone: .slate)
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
