//
//  ProgramsView.swift
//  Soulfull Gatherings
//
//  The Programs tab — "Digital Retreats" to a member: self-paced, multi-day
//  journeys.
//
//  Layout is "continue on top, catalog below" — a program in flight leads the
//  screen with the day the member is actually on, and everything else is
//  browsable underneath. Browsing needs no account; joining does.
//

import SwiftUI

struct ProgramsView: View {
    /// The Bool says whether this push has a matched zoom source behind it —
    /// catalog cards register one, the continue card and the cross-tab hand-off
    /// do not.
    var onOpenProgram: (Program, Bool) -> Void = { _, _ in }
    var onOpenDay: (Program, ProgramDay) -> Void = { _, _ in }
    /// A program another tab asked to open (Home's "Day N is open" card).
    /// Consumed once the catalog has actually loaded, then cleared.
    var pending: Binding<String?> = .constant(nil)
    var zoomNamespace: Namespace.ID?

    @State private var vm = ProgramsViewModel()
    /// Shared membership state. Read inside `body` so the observation registers.
    private let store = ProgramStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                if let active, let day = store.currentDay(active) {
                    continueCard(active, day: day)
                }

                if vm.isLoading && vm.programs.isEmpty {
                    ProgressView()
                        .tint(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let failure = vm.loadFailure, vm.programs.isEmpty {
                    unavailable(failure)
                } else if vm.programs.isEmpty {
                    emptyState
                } else {
                    catalog
                }

                Color.clear.frame(height: 120)
            }
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
        .background {
            PhotoBackdrop(imageName: active?.imageUrl ?? "onb-bg", blur: 26, darken: 0.8)
                .animation(.easeInOut(duration: 0.6), value: active?.id)
        }
        .task { await vm.load() }
        .task { await store.refresh() }
        // Coming back to the tab after practising elsewhere should reflect it:
        // the day may now be finished, and the next one may now be open.
        .task { await PracticeProgressStore.shared.refresh() }
        .task(id: active?.id) {
            guard let active else { return }
            await store.resolveContent(for: active)
            await store.syncCompletion(for: active)
        }
        // The hand-off can't run until the catalog is in: the id is all Home
        // has, and this screen is where the Program behind it lives.
        .onAppear(perform: consumePending)
        .onChange(of: pending.wrappedValue) { consumePending() }
        .onChange(of: vm.programs.map(\.id)) { consumePending() }
    }

    // MARK: - Which program leads the screen

    /// The program in flight. Most recently joined wins when there are several
    /// — it is the one they were last thinking about.
    private var active: Program? {
        vm.programs
            .filter { store.isEnrolled($0.id) && store.currentDay($0) != nil }
            .max { lhs, rhs in
                (store.enrollment(lhs.id)?.enrolledAt ?? .distantPast)
                    < (store.enrollment(rhs.id)?.enrolledAt ?? .distantPast)
            }
    }

    /// Opens whatever another tab handed us, then clears it so returning to
    /// this tab later doesn't re-push the same screen.
    private func consumePending() {
        guard let id = pending.wrappedValue,
              let program = vm.programs.first(where: { $0.id == id }) else { return }
        pending.wrappedValue = nil
        // Straight to the day when there is an open one; otherwise the program
        // itself, which is always a safe landing (and is what a guest, or
        // someone whose next day hasn't opened, should see).
        if let day = store.currentDay(program), store.state(program, day: day.day).isOpen {
            onOpenDay(program, day)
        } else {
            onOpenProgram(program, false)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SELF-PACED")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
            Text("Digital Retreats")
                .font(Theme.headline(38))
                .foregroundStyle(Theme.ink)
                .kerning(-0.3)
            Text("Guided journeys you walk one day at a time. Take them at whatever speed your life allows.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPhoto()
        .padding(.horizontal, 20)
    }

    // MARK: - Continue card

    @ViewBuilder
    private func continueCard(_ program: Program, day: ProgramDay) -> some View {
        let state = store.state(program, day: day.day)
        let total = program.authoredDays.count

        PressableCard(action: {
            if state.isOpen {
                onOpenDay(program, day)
            } else {
                onOpenProgram(program, false)
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    CatalogImage(day.imageUrl ?? program.imageUrl) { image in
                        image.resizable().scaledToFill()
                    }
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    LinearGradient(colors: [.clear, .black.opacity(0.2), .black.opacity(0.78)],
                                   startPoint: .top, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.isOpen ? "CONTINUE" : "UP NEXT")
                            .font(Theme.eyebrow(10))
                            .tracking(3)
                            .foregroundStyle(Theme.honey)
                        Text(program.title)
                            .font(Theme.headline(27))
                            .foregroundStyle(Theme.ink)
                            .kerning(-0.3)
                        HStack(spacing: 10) {
                            Text("DAY \(day.day) OF \(total)")
                                .font(Theme.eyebrow(10))
                                .tracking(2)
                                .foregroundStyle(Theme.inkSoft)
                            ProgressRule(fraction: store.fractionComplete(program), width: 80)
                        }
                    }
                    .onPhoto()
                    .padding(18)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(day.title)
                        .font(Theme.headline(19))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.2)
                    if let intention = day.intention {
                        Text(intention)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    dayStateLine(state, day: day, program: program)
                        .padding(.top, 2)
                    PresenceLine(programID: program.id)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .soulGlassCard()
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.glassBorderHigh, lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(program.title), day \(day.day) of \(total): \(day.title)")
    }

    /// The one line that says what the member can do right now. The two locked
    /// reasons get different words on purpose — "finish today first" and "come
    /// back tomorrow" are not the same message.
    @ViewBuilder
    private func dayStateLine(_ state: ProgramDayState, day: ProgramDay, program: Program) -> some View {
        let done = store.doneCount(of: day, in: program)
        let total = store.resolved(day, in: program).count

        switch state {
        case .open:
            HStack(spacing: 8) {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(done == 0 ? "Begin day \(day.day)"
                               : "\(done) of \(total) done — keep going")
                    .font(Theme.body(13, weight: .medium))
            }
            .foregroundStyle(Theme.honey)
        case .opens(let when):
            HStack(spacing: 8) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 13, weight: .medium))
                Text("Opens \(Self.relativeDay(when))")
                    .font(Theme.body(13))
            }
            .foregroundStyle(Theme.inkSoft)
        case .awaitingPreviousDay:
            Text("Finish the previous day first")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
        case .complete:
            Label("Complete", systemImage: "checkmark.seal.fill")
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
    }

    /// "tomorrow" / "on Friday" rather than a timestamp. A member does not
    /// think about their week in ISO dates.
    static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        if calendar.isDateInToday(date) { return "later today" }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: .now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if days > 0 && days < 7 {
            return "on \(date.formatted(.dateTime.weekday(.wide)))"
        }
        return "on \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    // MARK: - Catalog

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: active == nil ? "All digital retreats" : "More digital retreats")

            VStack(spacing: 14) {
                ForEach(vm.programs.filter { $0.id != active?.id }) { program in
                    PressableCard(action: { onOpenProgram(program, true) }) {
                        programCard(program)
                    }
                    .modifier(ProgramZoomSource(id: program.id, namespace: zoomNamespace))
                    .accessibilityIdentifier("program-card")
                    .listReveal()
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func programCard(_ program: Program) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                CatalogImage(program.imageUrl) { $0.resizable().scaledToFill() }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()

                LinearGradient(colors: [.black.opacity(0.35), .clear],
                               startPoint: .top, endPoint: .center)

                if let chip = stateChip(program) {
                    Text(chip.0)
                        .font(Theme.eyebrow(10))
                        .tracking(1.6)
                        .foregroundStyle(chip.1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .soulGlassCapsule()
                        .padding(12)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(program.title)
                    .font(Theme.headline(21))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                if let blurb = program.blurb {
                    Text(blurb)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(program.metaLine.uppercased()) · WITH \(program.lead.uppercased())")
                    .font(Theme.eyebrow(10))
                    .tracking(1.6)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
                PresenceLine(programID: program.id)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .soulGlassCard()
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.glassBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(program.title). \(program.metaLine), with \(program.lead)\(presenceSuffix(program.id))")
        .accessibilityHint("Opens the digital retreat")
    }

    /// ". 1.2k present" — the card sets its own VoiceOver label, which would
    /// otherwise drop the presence line.
    private func presenceSuffix(_ programID: String) -> String {
        PresenceStore.shared.presence(programID: programID).map { ". \($0.label)" } ?? ""
    }

    private func stateChip(_ program: Program) -> (String, Color)? {
        guard store.isEnrolled(program.id) else { return nil }
        if store.enrollment(program.id)?.completedAt != nil || store.currentDay(program) == nil {
            return ("COMPLETE", Theme.accent)
        }
        let done = store.completedDayCount(program.id)
        return ("DAY \(done + 1) OF \(program.authoredDays.count)", Theme.honey)
    }

    // MARK: - Empty / failure

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New digital retreats are on their way")
                .font(Theme.headline(20))
                .foregroundStyle(Theme.ink)
            Text("We're putting the finishing touches to the first ones. They'll appear here as soon as they're ready.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .soulGlassCard()
        .padding(.horizontal, 20)
    }

    private func unavailable(_ failure: ProgramsLoadFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(failure.title)
                .font(Theme.headline(20))
                .foregroundStyle(Theme.ink)
            Text(failure.detail)
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            SGPrimaryButton(title: "Try again") {
                Task { await vm.load(force: true) }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .soulGlassCard()
        .padding(.horizontal, 20)
    }
}

/// `matchedTransitionSource` only when the host handed us a namespace (previews
/// pass none).
private struct ProgramZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: "program-\(id)", in: namespace)
        } else {
            content
        }
    }
}

#Preview {
    ProgramsView()
        .preferredColorScheme(.dark)
}
