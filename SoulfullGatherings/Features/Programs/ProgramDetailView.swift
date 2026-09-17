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
    @Environment(\.dismiss) private var dismiss

    private var enrolled: Bool { store.isEnrolled(program.id) }
    private var days: [ProgramDay] { program.authoredDays }
    private var current: ProgramDay? { store.currentDay(program) }
    private var finished: Bool { enrolled && current == nil && !days.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                VStack(alignment: .leading, spacing: 24) {
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
                            .foregroundStyle(Theme.honey)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if days.isEmpty {
                        notReadyNote
                    } else {
                        dayList
                    }

                    if enrolled { leaveRow }
                }
                .padding(.horizontal, 20)

                Color.clear.frame(height: 120)
            }
        }
        .scrollIndicators(.hidden)
        .background { Theme.bg.ignoresSafeArea() }
        .overlay(alignment: .topLeading) {
            PracticeBackBar(label: "Programs")
                .padding(.horizontal, 20)
                .padding(.top, 6)
        }
        .task {
            await store.refresh()
            await store.resolveContent(for: program)
            await PracticeProgressStore.shared.refresh()
            await store.syncCompletion(for: program)
        }
        .confirmationDialog("Leave this program?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave program", role: .destructive) { leave() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("Your day-by-day progress in this program will be cleared. The practices you've done stay in your history.")
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
                    .font(Theme.headline(38))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.4)
                    .fixedSize(horizontal: false, vertical: true)
                Text("with \(program.lead)")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                if enrolled && !days.isEmpty {
                    HStack(spacing: 10) {
                        Text("\(store.completedDayCount(program.id)) OF \(days.count) DAYS")
                            .font(Theme.eyebrow(10))
                            .tracking(2)
                            .foregroundStyle(Theme.honey)
                        ProgressRule(fraction: store.fractionComplete(program), width: 90)
                    }
                    .padding(.top, 4)
                }
            }
            .onPhoto()
            .padding(20)
        }
    }

    // MARK: - Primary action

    @ViewBuilder
    private var primaryAction: some View {
        if days.isEmpty {
            EmptyView()
        } else if finished {
            SGPrimaryButton(title: "Begin again", icon: "arrow.counterclockwise") {
                confirmingLeave = true
            }
        } else if !enrolled {
            SGPrimaryButton(title: isJoining ? "Starting…" : "Start this program",
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
            HStack(spacing: 10) {
                Image(systemName: "moon.stars")
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
            .foregroundStyle(Theme.honey)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .soulGlassCard()
        }
    }

    // MARK: - Days

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "The days")
            VStack(spacing: 10) {
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
            HStack(alignment: .top, spacing: 14) {
                dayMarker(day, state: state)

                VStack(alignment: .leading, spacing: 4) {
                    Text(day.title)
                        .font(Theme.headline(17))
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .soulGlassCard()
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(state.isOpen && enrolled ? Theme.honey.opacity(0.4) : Theme.glassBorder,
                                  lineWidth: 1)
            )
            .opacity(enrolled && !state.isComplete && !state.isOpen ? 0.72 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("program-day-row")
        .accessibilityLabel("Day \(day.day), \(day.title)")
    }

    private func dayMarker(_ day: ProgramDay, state: ProgramDayState) -> some View {
        ZStack {
            Circle()
                .fill(state.isComplete ? Theme.accent.opacity(0.22) : Theme.ink.opacity(0.08))
                .frame(width: 38, height: 38)
            Circle()
                .strokeBorder(state.isComplete ? Theme.accent.opacity(0.5) : Theme.glassBorder, lineWidth: 1)
                .frame(width: 38, height: 38)

            if state.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
            } else {
                Text("\(day.day)")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(state.isOpen && enrolled ? Theme.honey : Theme.inkSoft)
            }
        }
    }

    @ViewBuilder
    private func dayRowStatus(_ day: ProgramDay, state: ProgramDayState) -> some View {
        let activities = store.resolved(day, in: program)
        let label: String = {
            guard enrolled else {
                return "\(activities.count) \(activities.count == 1 ? "practice" : "practices")"
            }
            switch state {
            case .complete(let when):
                return "Completed \(when.formatted(.dateTime.month(.abbreviated).day()))"
            case .open:
                let done = store.doneCount(of: day, in: program)
                return done == 0 ? "\(activities.count) practices · open now"
                                 : "\(done) of \(activities.count) done"
            case .opens(let when):
                return "Opens \(ProgramsView.relativeDay(when))"
            case .awaitingPreviousDay:
                return "Finish day \(day.day - 1) first"
            }
        }()

        HStack(spacing: 6) {
            if case .opens = state {
                Image(systemName: "moon.stars").font(.system(size: 10, weight: .medium))
            } else if case .awaitingPreviousDay = state, enrolled {
                Image(systemName: "lock").font(.system(size: 10, weight: .medium))
            }
            Text(label.uppercased())
                .font(Theme.eyebrow(10))
                .tracking(1.6)
        }
        .foregroundStyle(state.isOpen && enrolled ? Theme.honey : Theme.muted)
    }

    // MARK: - Bits

    private func closingCard(_ closing: ProgramClosing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("PROGRAM COMPLETE", systemImage: "checkmark.seal.fill")
                .font(Theme.eyebrow(10))
                .tracking(2)
                .foregroundStyle(Theme.accent)
            Text(closing.title)
                .font(Theme.headline(22))
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
        .padding(18)
        .soulGlassCard(tint: Theme.accent.opacity(0.1))
    }

    private var notReadyNote: some View {
        Text("The days of this program are still being written. It'll open here as soon as they are.")
            .font(Theme.body(14))
            .foregroundStyle(Theme.inkSoft)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .soulGlassCard()
    }

    private var leaveRow: some View {
        Button {
            Haptics.tap()
            confirmingLeave = true
        } label: {
            Text("Leave this program")
                .font(Theme.body(13))
                .underline()
                .foregroundStyle(Theme.muted)
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
                if let first = store.currentDay(program) { onOpenDay(first) }
            } catch {
                Log.data.error("Program enrolment failed: \(error.localizedDescription)")
                joinError = "Couldn't start this program. Please try again."
            }
        }
    }

    private func leave() {
        Task {
            do {
                try await store.leave(program)
                Haptics.tap()
            } catch {
                Log.data.error("Leaving program failed: \(error.localizedDescription)")
                joinError = "Couldn't leave this program. Please try again."
            }
        }
    }
}

#Preview {
    ProgramDetailView(program: Program.mock[0])
        .preferredColorScheme(.dark)
}
