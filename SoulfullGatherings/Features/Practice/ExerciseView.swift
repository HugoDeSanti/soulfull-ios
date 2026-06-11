//
//  ExerciseView.swift
//  Soulfull Gatherings
//
//  Exercises section: guided movement sequences. The list shows each routine;
//  the detail screen lays out its numbered steps with sets/reps.
//  Mock-driven until an `exercises` table is seeded.
//

import SwiftUI

struct ExerciseListView: View {
    let onOpen: (Exercise) -> Void
    private let exercises = Exercise.all

    var body: some View {
        PracticeListScaffold(
            title: PracticeMenuItem.exercises.title,
            blurb: PracticeMenuItem.exercises.blurb,
            systemImage: PracticeMenuItem.exercises.systemImage,
            backdrop: PracticeMenuItem.exercises.imageName
        ) {
            VStack(spacing: 10) {
                ForEach(exercises) { exercise in
                    PressableCard(action: { onOpen(exercise) }) {
                        exerciseRow(exercise)
                    }
                    .listReveal()
                }
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 14) {
            Image(exercise.imageUrl)
                .resizable().scaledToFill()
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
                PracticeBackBar(label: "Exercises")

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(exercise.focus.uppercased())
                        Text("·")
                        Text(exercise.durationLabel.uppercased())
                    }
                    .font(Theme.eyebrow(11))
                    .tracking(2)
                    .foregroundStyle(Theme.muted)

                    Text(exercise.title)
                        .font(Theme.headline(32))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(exercise.blurb)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("THE SEQUENCE")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)

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
        .background {
            PhotoBackdrop(imageName: exercise.imageUrl, blur: 24, darken: 0.8)
        }
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView(exercise: Exercise.all[1])
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
