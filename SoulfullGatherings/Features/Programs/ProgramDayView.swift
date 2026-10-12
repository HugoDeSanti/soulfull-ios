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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn

    @State private var nowPlaying: PracticeSession?
    /// Set when this visit is the one that completed the day, so the moment is
    /// celebrated exactly once rather than on every return to the screen.
    @State private var justCompleted = false

    private var resolution: ProgramDayResolution { store.resolution(day) }
    private var activities: [ResolvedActivity] { resolution.activities }
    /// Nothing to show yet, and something still on its way — a first visit
    /// offline, or before the libraries have been read.
    private var isWaiting: Bool { activities.isEmpty && !resolution.isSettled }
    private var doneCount: Int { store.doneCount(of: day, in: program) }
    private var state: ProgramDayState { store.state(program, day: day.day) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero
                VStack(alignment: .leading, spacing: 32) {
                    progressLine
                    activityList
                    if state.isComplete { afterCard }
                }
                .padding(.horizontal, Theme.gutter)
                Color.clear.frame(height: 120)
            }
        }
        .scrollIndicators(.hidden)
        // The hero runs up under the clock, as the retreat's and the recipe's
        // do, rather than stopping short of it on a strip of bare canvas. The
        // overlays below still keep to the safe area.
        .ignoresSafeArea(edges: .top)
        // Late, so the hero isn't cut while it fills the top; reaching past
        // the pinned Back link, so the page dissolves before it reaches it.
        .statusBarFade(fadeIn: 80...180, reach: 46)
        .background { Theme.bg.ignoresSafeArea() }
        .overlay(alignment: .topLeading) {
            PracticeBackBar(label: program.title)
                .padding(.horizontal, Theme.gutter)
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
                    .foregroundStyle(Theme.ember)
                Text(day.title)
                    .font(Theme.headline(34, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.6)
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
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Progress

    private var progressLine: some View {
        HStack(spacing: 12) {
            if state.isComplete {
                Label("Day complete", systemImage: "checkmark")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.accentSoft)
            } else if resolution.isSettled {
                // Only once every activity has an answer: with one still being
                // looked up, "1 of 1 done" and a full bar would claim a day that
                // can't actually close yet.
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

    /// The day's practices as a ruled list — each under a hairline, none in
    /// a box.
    private var activityList: some View {
        VStack(spacing: 0) {
            if isWaiting {
                ProgressView()
                    .tint(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
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
        return HStack(alignment: .top, spacing: 16) {
            ZStack {
                CatalogImage(item.content.imageUrl) { $0.resizable().scaledToFill() }
                    .frame(width: 68, height: 68)
                    .clipped()
                    .overlay {
                        if done {
                            Rectangle().fill(Color.black.opacity(0.5))
                        }
                    }
                Image(systemName: done ? "checkmark" : item.content.systemImage)
                    .font(.system(size: done ? 20 : 15, weight: .light))
                    .foregroundStyle(done ? Theme.accentSoft : Theme.ink)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .overlay(
                Rectangle()
                    .strokeBorder(done ? Theme.accentSoft.opacity(0.45) : Theme.glassBorder, lineWidth: Theme.hairline)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(item.content.title)
                    .font(Theme.headline(18, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(item.content.libraryLabel.uppercased()) · \(item.content.durationLabel.uppercased())")
                    .font(Theme.eyebrow(10))
                    .tracking(1.6)
                    .foregroundStyle(done ? Theme.accentSoft : Theme.muted)
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
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(index). \(item.content.title), \(item.content.libraryLabel), \(item.content.durationLabel)\(done ? ", done" : "")")
    }

    // MARK: - What happens next

    /// Open on the page under a hairline — words to read, nothing to tap.
    @ViewBuilder
    private var afterCard: some View {
        let next = program.authoredDays.first { $0.day == day.day + 1 }
        VStack(alignment: .leading, spacing: 10) {
            if let next {
                let nextState = store.state(program, day: next.day)
                Label("NEXT", systemImage: "moon.stars")
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(Theme.inkSoft)
                Text("Day \(next.day) · \(next.title)")
                    .font(Theme.headline(20, weight: .light))
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
                        .foregroundStyle(Theme.ember)
                }
            } else if let closing = program.curriculum?.closing {
                Label("DIGITAL RETREAT COMPLETE", systemImage: "checkmark")
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(Theme.accentSoft)
                Text(closing.title)
                    .font(Theme.headline(20, weight: .light))
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
        .padding(.top, 20)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
    }

    // MARK: - The moment the day closes

    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(Theme.accentSoft)
                    .breathing(scale: 1...1, opacity: 0.6...1)
                Text("Day \(day.day) complete")
                    .font(Theme.headline(26, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.4)
                Text(nextLine)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 28)
            .soulGlassCard()
            .padding(.horizontal, 34)
        }
        // Fades in and out where it stands — it used to grow from 96% as well.
        .transition(.opacity)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Theme.Motion.settle) { justCompleted = false } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .accessibilityHint("Double-tap to close")
        .accessibilityAction { withAnimation(Theme.Motion.settle) { justCompleted = false } }
        .task {
            // VoiceOver hears the moment rather than missing a card that
            // closes on its own — and keeps it until they dismiss it.
            if voiceOverOn {
                AccessibilityNotification.Announcement("Day \(day.day) complete. \(nextLine)").post()
                return
            }
            try? await Task.sleep(for: .seconds(3.4))
            withAnimation(Theme.Motion.reveal) { justCompleted = false }
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

    /// Asks whether the day is now finished, and celebrates if this visit is
    /// the one that finished it.
    ///
    /// Twice, spaced, on what this device knows. The written libraries record
    /// their dwell in `onDisappear` and the player on dismissal, and
    /// `PracticeProgressStore.record` applies each write locally at once — but
    /// either can land just after this screen comes back. Only then, once,
    /// does it read the server (a practice finished on another device). It
    /// used to force that read first: one that answered before the final write
    /// had landed replaced the fresher local copy, and the day didn't close.
    private func settle() async {
        await store.refresh()
        // Usually already done by the page that pushed this one; not when the
        // libraries couldn't be read then, and this visit is the retry.
        await store.resolveContent(for: program)
        for delay in [0.35, 1.6] {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            if await closeIfFinished() { return }
        }
        await history.refresh(force: true)
        guard !Task.isCancelled else { return }
        _ = await closeIfFinished()
    }

    private func closeIfFinished() async -> Bool {
        guard await store.syncCompletion(for: program) == day.day else { return false }
        Haptics.success()
        withAnimation(Theme.Motion.reveal) { justCompleted = true }
        return true
    }
}

// Its sample content (`Fixtures.swift`) exists only in DEBUG.
#if DEBUG
#Preview {
    ProgramDayView(program: Program.mock[0], day: Program.mock[0].authoredDays[0])
        .preferredColorScheme(.dark)
}
#endif
