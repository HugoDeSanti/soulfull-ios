//
//  ProgramDayView.swift
//  Soulfull Gatherings
//
//  One day of a program: its intention, and the two or three practices that
//  make it up.
//
//  Nothing here records progress itself. Each activity opens the normal screen
//  from the normal library — the player, a journal prompt, a movement sequence,
//  a recipe — and those write to `practice_plays` exactly as they do from the
//  Practice tab. This screen only *reads* that back and asks `ProgramStore`
//  whether the day is therefore finished.
//

import SwiftUI

struct ProgramDayView: View {
    let program: Program
    let day: ProgramDay
    /// Pushes for the written libraries. Sessions are a sheet, handled here.
    var onOpen: (ProgramActivityContent) -> Void = { _ in }

    private let store = ProgramStore.shared
    private let history = PracticeProgressStore.shared

    @State private var nowPlaying: PracticeSession?
    /// Set when this visit is the one that completed the day, so the moment is
    /// celebrated exactly once rather than on every return to the screen.
    @State private var justCompleted = false

    private var activities: [ResolvedActivity] { store.resolved(day, in: program) }
    private var doneCount: Int { store.doneCount(of: day, in: program) }
    private var state: ProgramDayState { store.state(program, day: day.day) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                VStack(alignment: .leading, spacing: 22) {
                    progressLine
                    activityList
                    if state.isComplete { afterCard }
                }
                .padding(.horizontal, 20)
                Color.clear.frame(height: 120)
            }
        }
        .scrollIndicators(.hidden)
        .background { Theme.bg.ignoresSafeArea() }
        .overlay(alignment: .topLeading) {
            PracticeBackBar(label: program.title)
                .padding(.horizontal, 20)
                .padding(.top, 6)
        }
        .overlay {
            if justCompleted { completionOverlay }
        }
        .task { await settle() }
        // A written practice writes its dwell on the way out, and the player on
        // dismissal — so re-read when either one lands us back here.
        .onChange(of: nowPlaying) { _, new in
            guard new == nil else { return }
            Task { await settle() }
        }
        .sheet(item: $nowPlaying) { session in
            PracticePlayerView(media: session.media)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            CatalogImage(day.imageUrl ?? program.imageUrl) { $0.resizable().scaledToFill() }
                .frame(height: 340)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0.2), location: 0.45),
                    .init(color: Theme.bg.opacity(0.95), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("DAY \(day.day) OF \(program.authoredDays.count)")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.honey)
                Text(day.title)
                    .font(Theme.headline(34))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
                    .fixedSize(horizontal: false, vertical: true)
                if let intention = day.intention {
                    Text(intention)
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.inkOnPhoto)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onPhoto()
            .padding(20)
        }
    }

    // MARK: - Progress

    private var progressLine: some View {
        HStack(spacing: 12) {
            if state.isComplete {
                Label("Day complete", systemImage: "checkmark.seal.fill")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.accent)
            } else {
                Text("\(doneCount) of \(activities.count) done")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                ProgressRule(fraction: activities.isEmpty ? 0
                                       : Double(doneCount) / Double(activities.count),
                             width: 90)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Activities

    private var activityList: some View {
        VStack(spacing: 10) {
            ForEach(Array(activities.enumerated()), id: \.element.id) { index, item in
                PressableCard(action: { open(item) }) {
                    activityRow(item, index: index + 1)
                }
                .accessibilityIdentifier("program-activity-row")
                .listReveal()
            }
        }
    }

    private func activityRow(_ item: ResolvedActivity, index: Int) -> some View {
        let done = store.isDone(item.activity, in: program, day: day.day)
        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                CatalogImage(item.content.imageUrl) { $0.resizable().scaledToFill() }
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        if done {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.45))
                        }
                    }
                Image(systemName: done ? "checkmark" : item.content.systemImage)
                    .font(.system(size: done ? 20 : 15, weight: .bold))
                    .foregroundStyle(done ? Theme.accent : .white)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(done ? Theme.accent.opacity(0.45) : Theme.glassBorder, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.content.title)
                    .font(Theme.headline(17))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(item.content.libraryLabel.uppercased()) · \(item.content.durationLabel.uppercased())")
                    .font(Theme.eyebrow(10))
                    .tracking(1.6)
                    .foregroundStyle(done ? Theme.accent : Theme.muted)
                if let note = item.note {
                    Text(note)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .soulGlassCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(done ? Theme.accent.opacity(0.35) : Theme.glassBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(index). \(item.content.title), \(item.content.libraryLabel), \(item.content.durationLabel)\(done ? ", done" : "")")
    }

    // MARK: - What happens next

    @ViewBuilder
    private var afterCard: some View {
        let next = program.authoredDays.first { $0.day == day.day + 1 }
        VStack(alignment: .leading, spacing: 8) {
            if let next {
                let nextState = store.state(program, day: next.day)
                Label("NEXT", systemImage: "moon.stars")
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(Theme.inkSoft)
                Text("Day \(next.day) · \(next.title)")
                    .font(Theme.headline(19))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                if case .opens(let when) = nextState {
                    Text("Opens \(ProgramsView.relativeDay(when)). Rest is part of it — we'll let you know when it's ready.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("It's open now, whenever you are.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.honey)
                }
            } else if let closing = program.curriculum?.closing {
                Label("PROGRAM COMPLETE", systemImage: "checkmark.seal.fill")
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(Theme.accent)
                Text(closing.title)
                    .font(Theme.headline(20))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(closing.body)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .soulGlassCard(tint: Theme.accent.opacity(0.08))
    }

    // MARK: - The moment the day closes

    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .breathing()
                Text("Day \(day.day) complete")
                    .font(Theme.headline(26))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
                Text(nextLine)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 34)
            .padding(.horizontal, 26)
            .soulGlassCard()
            .padding(.horizontal, 34)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { justCompleted = false } }
        .task {
            try? await Task.sleep(for: .seconds(3.4))
            withAnimation(.easeOut(duration: 0.3)) { justCompleted = false }
        }
    }

    private var nextLine: String {
        guard let next = program.authoredDays.first(where: { $0.day == day.day + 1 }) else {
            return "You've finished \(program.title)."
        }
        if case .opens(let when) = store.state(program, day: next.day) {
            return "Day \(next.day) opens \(ProgramsView.relativeDay(when)). Rest is part of it."
        }
        return "Day \(next.day) is ready when you are."
    }

    // MARK: - Actions

    private func open(_ item: ResolvedActivity) {
        switch item.content {
        case .session(let session):
            nowPlaying = session
        case .journal, .exercise, .recipe:
            onOpen(item.content)
        }
    }

    /// Re-reads practice history and asks whether the day is now finished.
    ///
    /// Twice, spaced. The written libraries write their dwell in `onDisappear`
    /// and the player on dismissal, so the row can still be in flight when this
    /// screen comes back — a single immediate read would show the practice
    /// undone and, worse, decline to close a day that is actually complete
    /// until the member left and returned.
    private func settle() async {
        await store.refresh()
        for delay in [0.35, 1.6] {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await history.refresh(force: true)
            if await store.syncCompletion(for: program) == day.day {
                Haptics.success()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { justCompleted = true }
                return
            }
        }
    }
}

#Preview {
    ProgramDayView(program: Program.mock[0], day: Program.mock[0].authoredDays[0])
        .preferredColorScheme(.dark)
}
