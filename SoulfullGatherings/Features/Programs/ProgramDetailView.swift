//
//  ProgramDetailView.swift
//  Soulfull Gatherings
//
//  One program: what it is, and the days it is made of.
//
//  Open to a guest — the whole arc of the program is readable without an
//  account. The gate is on *joining*, which is the moment it stops being
//  browsing and starts being theirs.
//

import SwiftUI

struct ProgramDetailView: View {
    let program: Program
    var onOpenDay: (ProgramDay) -> Void = { _ in }
    /// Injected by `ProgramsRoot` so this view stays unaware of auth. Defaults
    /// to running straight through, which keeps previews working.
    var requireAccount: (@escaping () -> Void) -> Void = { $0() }

    private let store = ProgramStore.shared
    @State private var isJoining = false
    @State private var joinError: String?
    @State private var confirmingLeave = false
    @State private var confirmingRestart = false
    @Environment(\.dismiss) private var dismiss

    private var enrolled: Bool { store.isEnrolled(program.id) }
    private var days: [ProgramDay] { program.authoredDays }
    private var current: ProgramDay? { store.currentDay(program) }
    private var finished: Bool { enrolled && current == nil && !days.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero
                VStack(alignment: .leading, spacing: 40) {
                    if let overview = program.curriculum?.overview {
                        Text(overview)
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.inkSoft)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if finished, let closing = program.curriculum?.closing {
                        closingCard(closing)
                    }

                    primaryAction

                    if let joinError {
                        Text(joinError)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.ember)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    GuideCard(instructorID: program.instructorID, from: program.title)

                    if days.isEmpty {
                        notReadyNote
                    } else {
                        dayList
                    }

                    if enrolled { leaveRow }
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
        .statusBarFade(fadeIn: 130...230, reach: 46)
        .background { Theme.bg.ignoresSafeArea() }
        .overlay(alignment: .topLeading) {
            PracticeBackBar(label: "Digital Retreats")
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 6)
        }
        .task {
            await store.refresh()
            await store.resolveContent(for: program)
            await PracticeProgressStore.shared.refresh()
            await store.syncCompletion(for: program)
        }
        .confirmationDialog("Leave this digital retreat?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave digital retreat", role: .destructive) { leave() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("Your day-by-day progress in this digital retreat will be cleared. The practices you've done stay in your history.")
        }
        // Its own question: "Begin again" used to ask "Leave this digital
        // retreat?" and then only leave, so the member had to start it again
        // by hand.
        .confirmationDialog("Begin this digital retreat again?", isPresented: $confirmingRestart, titleVisibility: .visible) {
            Button("Begin again") { restart() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("You'll start again from Day 1, a day at a time. The practices you've done stay in your history.")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            CatalogImage(program.imageUrl) { $0.resizable().scaledToFill() }
                .frame(height: 420)
                .frame(maxWidth: .infinity)
                .clipped()

            // The detail hero has no PhotoBackdrop behind it to scrim, so it
            // carries its own — held through the middle rather than falling
            // away, exactly as RetreatDetailView's does.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0.22), location: 0.45),
                    .init(color: Theme.bg.opacity(0.95), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(program.metaLine.uppercased())
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)
                Text(program.title)
                    .font(Theme.headline(38, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text("with \(program.lead)")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                PresenceLine(programID: program.id, faceSize: 22)
                    .padding(.top, 4)
                if enrolled && !days.isEmpty {
                    HStack(spacing: 10) {
                        Text("\(store.completedDayCount(program.id)) OF \(days.count) DAYS")
                            .font(Theme.eyebrow(10))
                            .tracking(2)
                            .foregroundStyle(Theme.ember)
                        ProgressRule(fraction: store.fractionComplete(program), width: 90)
                    }
                    .padding(.top, 4)
                }
            }
            .onPhoto()
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Primary action

    @ViewBuilder
    private var primaryAction: some View {
        if days.isEmpty {
            EmptyView()
        } else if finished {
            SGPrimaryButton(title: isJoining ? "Starting…" : "Begin again",
                            enabled: !isJoining,
                            icon: "arrow.counterclockwise") {
                confirmingRestart = true
            }
        } else if !enrolled {
            SGPrimaryButton(title: isJoining ? "Starting…" : "Start this digital retreat",
                            enabled: !isJoining,
                            filled: true,
                            icon: "arrow.forward") {
                requireAccount { join() }
            }
        } else if let current, store.state(program, day: current.day).isOpen {
            SGPrimaryButton(title: "Open day \(current.day)", filled: true, icon: "arrow.forward") {
                Haptics.bump()
                onOpenDay(current)
            }
        } else if let current, case .opens(let when) = store.state(program, day: current.day) {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 15, weight: .light))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day \(current.day) opens \(ProgramsView.relativeDay(when))")
                        .font(Theme.body(14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("Rest is part of it. We'll let you know.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ember)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .soulGlassCard()
        }
    }

    // MARK: - Days

    /// The days as a ruled list — each under a hairline, none in a box.
    private var dayList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "The days")
                // `SectionLabel` brings its own page margin; this list already
                // sits inside one.
                .padding(.horizontal, -Theme.gutter)
            VStack(spacing: 0) {
                ForEach(days) { day in
                    dayRow(day)
                        .listReveal()
                }
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ day: ProgramDay) -> some View {
        let state = enrolled ? store.state(program, day: day.day) : .awaitingPreviousDay
        let openable = enrolled && state.isOpen

        PressableCard(haptic: openable, action: {
            guard openable else {
                // A locked day is not a dead tap: say why, quietly.
                Haptics.tap()
                return
            }
            onOpenDay(day)
        }) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                dayMarker(day, state: state)

                VStack(alignment: .leading, spacing: 5) {
                    Text(day.title)
                        .font(Theme.headline(18, weight: .light))
                        .foregroundStyle(enrolled && !state.isComplete && !state.isOpen ? Theme.inkSoft : Theme.ink)
                        .kerning(-0.2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let intention = day.intention {
                        Text(intention)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.muted)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    dayRowStatus(day, state: state)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)

                if openable {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.line).frame(height: 0.5)
            }
            .contentShape(Rectangle())
            .opacity(enrolled && !state.isComplete && !state.isOpen ? 0.6 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("program-day-row")
        // The status is what tells an open day from a locked or finished one —
        // without it every row read the same. A row that can't be opened isn't
        // announced as a button: double-tapping it only buzzes.
        .accessibilityLabel("Day \(day.day), \(day.title). \(statusText(day, state: state))")
        .accessibilityRemoveTraits(openable ? [] : .isButton)
    }

    /// The day as a folio numeral — "01" — with no circle round it. Ink
    /// when it's the day to open, moss once it's done, muted otherwise; the
    /// status line under the title says the rest in words.
    private func dayMarker(_ day: ProgramDay, state: ProgramDayState) -> some View {
        Text(String(format: "%02d", day.day))
            .font(Theme.body(12, weight: .medium))
            .tracking(1.5)
            .monospacedDigit()
            .foregroundStyle(state.isComplete ? Theme.accentSoft
                             : (state.isOpen && enrolled ? Theme.ink : Theme.muted))
            .frame(width: 24, alignment: .leading)
    }

    /// How many practices a day holds. The authored count until every one has
    /// been looked up — a written library still loading (or offline on a fresh
    /// install) used to make every row read "0 practices".
    private func practiceCount(_ day: ProgramDay) -> Int {
        let resolution = store.resolution(day)
        return resolution.isSettled ? resolution.activities.count : day.activities.count
    }

    /// The row's one-line status, also what VoiceOver reads after the title.
    private func statusText(_ day: ProgramDay, state: ProgramDayState) -> String {
        let count = practiceCount(day)
        let practices = "\(count) \(count == 1 ? "practice" : "practices")"
        guard enrolled else { return practices }
        switch state {
        case .complete(let when):
            return "Completed \(when.formatted(.dateTime.month(.abbreviated).day()))"
        case .open:
            let done = store.doneCount(of: day, in: program)
            return done == 0 ? "\(practices) · open now" : "\(done) of \(count) done"
        case .opens(let when):
            return "Opens \(ProgramsView.relativeDay(when))"
        case .awaitingPreviousDay:
            return "Finish day \(day.day - 1) first"
        }
    }

    @ViewBuilder
    private func dayRowStatus(_ day: ProgramDay, state: ProgramDayState) -> some View {
        let label = statusText(day, state: state)

        HStack(spacing: 6) {
            if case .opens = state {
                Image(systemName: "moon.stars").font(.system(size: 10, weight: .light))
            } else if case .awaitingPreviousDay = state, enrolled {
                Image(systemName: "lock").font(.system(size: 10, weight: .light))
            }
            Text(label.uppercased())
                .font(Theme.eyebrow(10))
                .tracking(1.6)
        }
        .foregroundStyle(state.isOpen && enrolled ? Theme.ember : Theme.muted)
    }

    // MARK: - Bits

    /// Open on the page under a hairline — words to read, nothing to tap.
    private func closingCard(_ closing: ProgramClosing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("DIGITAL RETREAT COMPLETE", systemImage: "checkmark")
                .font(Theme.eyebrow(10))
                .tracking(2)
                .foregroundStyle(Theme.accentSoft)
            Text(closing.title)
                .font(Theme.headline(22, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.2)
                .fixedSize(horizontal: false, vertical: true)
            Text(closing.body)
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
    }

    private var notReadyNote: some View {
        Text("The days of this digital retreat are still being written. It'll open here as soon as they are.")
            .font(Theme.body(14))
            .foregroundStyle(Theme.inkSoft)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.line).frame(height: 0.5)
            }
    }

    private var leaveRow: some View {
        Button {
            Haptics.tap()
            confirmingLeave = true
        } label: {
            Text("Leave this digital retreat")
                .font(Theme.body(13))
                .underline()
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func join() {
        guard !isJoining else { return }
        isJoining = true
        joinError = nil
        Task {
            defer { isJoining = false }
            do {
                try await store.enroll(in: program)
                Haptics.success()
                await store.resolveContent(for: program)
                // The day they're on, and only if it's open: a member who was
                // already part-way through (and has just signed in) may be
                // waiting for tomorrow's day, which this page already explains.
                if let current = store.currentDay(program), store.state(program, day: current.day).isOpen {
                    onOpenDay(current)
                }
            } catch {
                Log.data.error("Program enrolment failed: \(error.localizedDescription)")
                joinError = "Couldn't start this digital retreat. Please try again."
            }
        }
    }

    /// Clears the finished run, then joins afresh — which lands on Day 1.
    private func restart() {
        guard !isJoining else { return }
        Task {
            do {
                try await store.leave(program)
            } catch {
                Log.data.error("Restarting program failed: \(error.localizedDescription)")
                joinError = "Couldn't begin this digital retreat again. Please try again."
                return
            }
            join()
        }
    }

    private func leave() {
        Task {
            do {
                try await store.leave(program)
                Haptics.tap()
            } catch {
                Log.data.error("Leaving program failed: \(error.localizedDescription)")
                joinError = "Couldn't leave this digital retreat. Please try again."
            }
        }
    }
}

#Preview {
    ProgramDetailView(program: Program.mock[0])
        .preferredColorScheme(.dark)
}
