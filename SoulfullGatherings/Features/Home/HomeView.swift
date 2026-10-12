//
//  HomeView.swift
//  Soulfull Gatherings
//
//  The main landing screen, on its photograph. Sections fade up from
//  half-light as they scroll in, a mood is a word underlined when chosen,
//  and the cards beneath the moods (an open day, Continue, the ritual) stack
//  close as one section. The ritual card holds a slow ember wash — the one
//  warm thing on the page. The two shelves at the foot — digital retreats, then upcoming
//  gatherings — are photographs with their names set beneath, and
//  hand off to their own tabs.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var vm = HomeViewModel()
    /// Server-held practice history — the continue card and the streak line.
    /// Read inside `body`, which is what registers the observation.
    private let history = PracticeProgressStore.shared
    /// Program enrolment, for the "Day N is open" line. Read inside `body`.
    private let programs = ProgramStore.shared

    /// Jump to the Gatherings tab.
    let onOpenRetreats: () -> Void
    /// Jump to the Gatherings tab and open that retreat there.
    let onOpenRetreat: (Retreat) -> Void
    /// Jump to a section of the Practice library (from the ritual card).
    var onOpenPractice: (PracticeMenuItem) -> Void = { _ in }
    /// Jump to the Digital Retreats tab. A non-nil id opens that program; nil
    /// just switches to the tab.
    var onOpenProgram: (String?) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionGap) {
                // One opening, not two sections: the greeting asks the mood
                // question, so the question follows it at a header's gap, with
                // no rule between them. A section's gap and a rule there set
                // the greeting adrift and dropped the member's cards to
                // mid-screen.
                VStack(spacing: Theme.headerGap) {
                    header
                    today
                }
                // Hidden until the `programs` table is seeded — see HomeViewModel.
                if !vm.programs.isEmpty {
                    section { digitalRetreats }
                }
                // Last on the page: the gatherings have a tab of their own now,
                // so this is a glimpse rather than the way in.
                section { upcomingGatherings }
            }
            .padding(.top, 32)
            // Clear of the docked bar by a section's gap, as the sections are
            // of each other.
            .padding(.bottom, 120)
            // The day card and the Continue card arrive after the page has
            // drawn, above the ritual. Animated, the ritual eases down rather
            // than jumping out from under a reaching thumb.
            .animation(reduceMotion ? nil : Theme.Motion.settle, value: openProgramDay?.1.id)
            .animation(reduceMotion ? nil : Theme.Motion.settle, value: history.resumable?.id)
        }
        .scrollIndicators(.hidden)
        .statusBarFade()
        .background {
            PhotoBackdrop(imageName: "home-bg", blur: 3, darken: 0.74)
        }
        .task { await vm.load() }
        .task { await history.refresh() }
        .task { await programs.refresh() }
    }

    /// The program day that is open right now, if any. Nothing is invented:
    /// with no enrolment, or with the next day still locked, there is no card.
    private var openProgramDay: (Program, ProgramDay)? {
        for program in vm.programs where programs.isEnrolled(program.id) {
            guard let day = programs.currentDay(program),
                  programs.state(program, day: day.day).isOpen else { continue }
            return (program, day)
        }
        return nil
    }

    /// Shared scroll-in reveal: sections fade up from half-light as they
    /// enter from the bottom; nothing happens scrolling back past the top.
    /// Light only — they used to rise out of a blur as well; nothing travels
    /// now.
    private func section(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .scrollTransition(.interactive(timingCurve: .easeOut), axis: .vertical) { view, phase in
                view.opacity(1 - max(phase.value, 0) * 0.6) // only the bottom edge
            }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 40) {
            Image("soulfull-logo-white")
                .resizable().scaledToFit()
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 8) {
                // Once per body: it walks the whole practice ledger.
                let streak = history.streakDays
                Text(vm.greeting.uppercased())
                    .font(Theme.eyebrow(12))
                    .tracking(2)
                    // Ink, not inkSoft: it sits on the brightest, haziest
                    // part of home-bg, where grey caps disappear.
                    .foregroundStyle(Theme.ink)
                Text("\(HomeViewModel.greetingName(settings.name)).")
                    .font(Theme.headline(42, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.8)
                // A streak is only worth naming once it is one; a single day
                // is just today, and calling that a run is exactly the
                // manufactured momentum this screen had removed from it.
                if streak >= 2 {
                    HStack(spacing: 7) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                        Text("\(streak) days in a row")
                            .font(Theme.eyebrow(11))
                            .tracking(1.5)
                    }
                    .foregroundStyle(Theme.ember)
                    .padding(.top, 8)
                    .accessibilityLabel("\(streak) day practice streak")
                }

                Text("Take your time. We're here with you.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Sits on the brightest part of home-bg (blur 3) — see onPhoto().
            .onPhoto()
            .padding(.horizontal, Theme.gutter)
        }
    }

    /// The question and what the day holds, as one section: the cards are
    /// stacked close under the moods rather than spaced as sections of their
    /// own, which left each one floating alone (owner, 2026-10-10).
    private var today: some View {
        VStack(spacing: 12) {
            // The words' 44pt targets leave 13pt beneath them, so the cards
            // start ~28pt under the words and stack 12pt apart.
            section { moodRow }
            // Picking up something already begun beats being handed
            // something new, so it sits above the ritual. Absent entirely
            // when there's nothing under way — no invented state.
            // The in-app half of the day-unlock nudge, for everyone who
            // declined notifications — and for everyone who has them and
            // opened the app before 8am anyway.
            if let open = openProgramDay {
                section { programDayCard(open.0, day: open.1) }
            }
            if let resume = history.resumable {
                section { continueCard(resume) }
            }
            section { todaysRitual }
        }
    }

    private var moodRow: some View {
        // Label to words reads as label to photo on the shelves (20pt); the
        // words' own 13pt of target makes up the rest.
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: "How do you feel?", ruled: false)
                .onPhoto()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 26) {
                    ForEach(vm.moods) { m in
                        moodChip(m)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    /// A mood is a word, as Open sets its tabs: grey until chosen, then ink
    /// with a hairline under it. Nothing grows or glows — the line fades in.
    private func moodChip(_ m: MoodChip) -> some View {
        let selected = vm.selectedMood == m.id
        return Button {
            vm.tapMood(m.id)
        } label: {
            Text(m.label)
                .font(Theme.body(15, weight: .light))
                .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.ink)
                        .frame(height: 1)
                        .offset(y: 7)
                        .opacity(selected ? 1 : 0)
                }
                .onPhoto()
                // A 44pt target around a word.
                .padding(.vertical, 13)
                .contentShape(Rectangle())
                .animation(Theme.Motion.settle, value: selected)
        }
        .buttonStyle(SoulPressableStyle(hapticOnPress: false))
        .accessibilityLabel(m.label)
        .accessibilityHint("Suggests a practice for feeling \(m.label.lowercased())")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// "Continue where you left off" — the one piece of real continuity the app
    /// has. Routes to the section the practice lives in rather than deep-linking
    /// the item, so it behaves identically for a half-played meditation and a
    /// half-read recipe.
    private func continueCard(_ progress: PracticeProgress) -> some View {
        PressableCard(action: { onOpenPractice(progress.menuItem) }) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("CONTINUE")
                        .font(Theme.eyebrow(10))
                        .tracking(2)
                        .foregroundStyle(Theme.ember)
                    Text(progress.title)
                        .font(Theme.headline(20, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        ProgressRule(fraction: progress.fraction, width: 64)
                        if let remaining = progress.remainingLabel {
                            Text(remaining)
                                .font(Theme.eyebrow(10))
                                .tracking(1)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 8)
                // A play mark in a hairline, not a filled disc.
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .overlay(Theme.controlShape.strokeBorder(Theme.ink.opacity(0.7), lineWidth: Theme.hairline))
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .soulGlassCard()
            .contentShape(Rectangle())
        }
        .padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Continue \(progress.title)")
        .accessibilityHint("Opens \(progress.menuItem.title)")
        .accessibilityAddTraits(.isButton)
    }

    private var todaysRitual: some View {
        PressableCard(action: { onOpenPractice(vm.ritualDestination) }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.mood == nil ? "TODAY'S RITUAL" : "BECAUSE YOU FEEL \(vm.mood!.label.uppercased())")
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(Theme.ink.opacity(0.8))
                    .padding(.bottom, 6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(vm.ritualTitle)
                    .font(Theme.headline(28, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.5)
                    .fixedSize(horizontal: false, vertical: true)
                Text(vm.ritualLead)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text("Begin now")
                        .font(Theme.body(12, weight: .medium))
                        .tracking(0.4)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .light))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(
                    Theme.controlShape.strokeBorder(Theme.ink.opacity(0.7), lineWidth: Theme.hairline)
                )
                .padding(.top, 28)
            }
            .animation(Theme.Motion.settle, value: vm.selectedMood)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 20 across, as the day and Continue cards stacked above it, so
            // the three start their lines on one edge.
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background {
                // The page's one warm thing: a slow ember wash falling from
                // the card's top edge, as Open lays its daily card.
                Atmosphere(tone: .ember, reach: 1.15, intensity: 1, fillsScreen: false)
            }
            .clipShape(Theme.cardShape)
            .overlay(
                Theme.cardShape.strokeBorder(Theme.glassBorder, lineWidth: Theme.hairline)
            )
        }
        .padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vm.ritualTitle). \(vm.ritualLead)")
        .accessibilityHint("Opens \(vm.ritualDestination.title)")
        .accessibilityAddTraits(.isButton)
    }

    private var upcomingGatherings: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(title: "Upcoming gatherings", action: "ALL",
                         actionLabel: "All gatherings") {
                onOpenRetreats()
            }
            .onPhoto()

            if let failure = vm.retreatsFailure {
                retreatsUnavailable(failure)
            } else if vm.retreats.isEmpty {
                // Not a bare heading over nothing: the shelf holds its height
                // while the first read is out, and says so when nothing is
                // announced.
                Group {
                    if vm.retreatsLoaded {
                        Text("New gatherings are on their way. Dates appear here as they're announced.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.inkOnPhoto)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onPhoto()
                    } else {
                        ProgressView()
                            .tint(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 150)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(vm.retreats.prefix(5)) { r in
                            retreatCard(r)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            }
        }
    }

    /// Shown in place of the shelf when there is no catalog to show. It used to
    /// fill with `Retreat.mock` instead, which put finished retreats in front
    /// of an offline user as if they were real — see `RetreatsLoadFailure`.
    private func retreatsUnavailable(_ failure: RetreatsLoadFailure) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: failure == .offline ? "wifi.slash" : "exclamationmark.triangle")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(failure.title)
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(failure.detail)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .soulGlassCard()
        .padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(failure.title). \(failure.detail)")
    }

    /// A photograph with its name set beneath on the page — no box
    /// around it, as Open lays its shelves.
    private func retreatCard(_ r: Retreat) -> some View {
        PressableCard(action: { onOpenRetreat(r) }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    CatalogImage(r.imageUrl) { image in
                        image
                            .resizable().scaledToFill()
                            .frame(width: 260, height: 170)
                            .clipped()
                    }
                    .frame(width: 260, height: 170)
                    .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom)
                    Text("\(r.country) · \(r.when)".uppercased())
                        .font(Theme.eyebrow(10))
                        .tracking(2)
                        .foregroundStyle(Theme.ink)
                        .padding(14)
                }
                .frame(width: 260, height: 170)
                .clipShape(Theme.cardShape)

                VStack(alignment: .leading, spacing: 4) {
                    Text(r.name)
                        .font(Theme.headline(20, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.3)
                    Text("\(r.durationDays) days · \(r.maxGuests) guests")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkSoft)
                }
                // Set beneath the photo, on the page's own photograph.
                .onPhoto()
                .padding(.top, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 260)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.name), \(r.country). \(r.when). \(r.durationDays) days, \(r.maxGuests) guests")
        .accessibilityHint("Opens retreat details")
    }

    private var digitalRetreats: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Both the "ALL" action and pressable cards came back when the
            // Digital Retreats tab gave them somewhere to go — see the note
            // that used to sit here about the shelf being informational.
            SectionLabel(title: "Digital Retreats", action: "ALL",
                         actionLabel: "All digital retreats") { onOpenProgram(nil) }
                .onPhoto()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(vm.programs) { p in
                        PressableCard(action: { onOpenProgram(p.id) }) {
                            programCard(p)
                        }
                        .accessibilityIdentifier("home-program-card")
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        }
    }

    private func programCard(_ p: Program) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                CatalogImage(p.imageUrl) { image in
                    image
                        .resizable().scaledToFill()
                        .frame(width: 260, height: 200)
                        .clipped()
                }
                .frame(width: 260, height: 200)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.62)],
                    startPoint: .top, endPoint: .bottom
                )

                Text("\(p.metaLine) · DIGITAL".uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(Theme.ink)
                    .padding(14)
            }
            .frame(width: 260, height: 200)
            .clipShape(Theme.cardShape)

            VStack(alignment: .leading, spacing: 0) {
                // Set beneath the photo, on the page's own photograph.
                Group {
                    Text(p.title)
                        .font(Theme.headline(20, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.3)
                        .lineLimit(2)
                    Text("with \(p.lead)")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 4)
                }
                .onPhoto()
                // Takes no room until someone is present, so the shelf ends
                // where its copy does, a section's gap above the next.
                PresenceLine(programID: p.id, faceSize: 18, topPadding: 10)
            }
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 260)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.title), with \(p.lead), \(p.days) day digital retreat\(PresenceStore.shared.presence(programID: p.id).map { ", \($0.label)" } ?? "")")
        .accessibilityHint("Opens the digital retreat")
    }

    // MARK: - "Day N is open"

    /// The in-app half of the unlock nudge. Deliberately quiet and specific:
    /// it names the day and its intention, so it reads as an invitation rather
    /// than a notification badge.
    private func programDayCard(_ program: Program, day: ProgramDay) -> some View {
        PressableCard(action: { onOpenProgram(program.id) }) {
            HStack(alignment: .top, spacing: 14) {
                CatalogImage(day.imageUrl ?? program.imageUrl) { $0.resizable().scaledToFill() }
                    .frame(width: 64, height: 64)
                    .clipShape(Theme.controlShape)

                VStack(alignment: .leading, spacing: 4) {
                    Text("DAY \(day.day) IS OPEN")
                        .font(Theme.eyebrow(10))
                        .tracking(2)
                        .foregroundStyle(Theme.ember)
                    Text(day.title)
                        .font(Theme.headline(20, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.2)
                        .fixedSize(horizontal: false, vertical: true)
                    // inkSoft, as the Continue card's "N MIN LEFT" beneath it:
                    // muted vanished on the frost wherever the photo is light.
                    Text(program.title)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 6)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .soulGlassCard()
            .padding(.horizontal, Theme.gutter)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Day \(day.day) of \(program.title) is open: \(day.title)")
        .accessibilityHint("Opens the day")
    }

}

#Preview {
    let a = AppState()
    a.settings.name = MemberName(first: "Mara")
    return HomeView(onOpenRetreats: {}, onOpenRetreat: { _ in })
        .environment(a)
        .environment(a.settings)
}
