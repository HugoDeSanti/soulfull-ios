//
//  GuideDashboardView.swift
//  Soulfull Gatherings
//
//  A guide's numbers, for the guide alone: this month so far, the people who
//  practiced with them month by month, what each past month's pool paid
//  them, and how each practice is doing. Opened from the card at the top of
//  their You tab, which only a member linked to a guide ever sees.
//
//  Every figure comes from `guide_dashboard()` (0026), which reads the same
//  view the payout run does, so the dashboard and the payment can't disagree.
//  A month whose pool the team hasn't set shows the share and no amount:
//  nothing here is estimated from a pool that doesn't exist yet.
//

import SwiftUI

// MARK: - The card on the You tab

struct GuideSummaryCard: View {
    let dashboard: GuideDashboard
    let action: () -> Void

    var body: some View {
        let month = dashboard.current
        PressableCard(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("GUIDE DASHBOARD")
                        .font(Theme.eyebrow(10))
                        .tracking(3)
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(Theme.muted)
                }
                Text("\(dashboard.thisMonth.name()) so far")
                    .font(Theme.headline(22, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.4)
                HStack(alignment: .top, spacing: 12) {
                    GuideFigure(value: month.people.formatted(), label: "People")
                    GuideFigure(value: month.minutesHeard.formatted(), label: "Min heard")
                    GuideFigure(value: GuideCopy.amount(month.standing(thisMonth: dashboard.thisMonth)) ?? "Pending",
                                label: GuideCopy.amountLabel(month.standing(thisMonth: dashboard.thisMonth)))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .soulGlassCard()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your guide dashboard")
        .accessibilityIdentifier("guide-dashboard-card")
    }
}

// MARK: - The dashboard

struct GuideDashboardView: View {
    let vm: GuideDashboardViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let dashboard = vm.dashboard {
                    content(dashboard)
                } else if vm.hasLoaded {
                    // Unlinked while the sheet was open: say so rather than
                    // leave the last guide's figures up.
                    unlinked
                        .padding(.top, 160)
                } else {
                    ProgressView()
                        .tint(Theme.ink)
                        .padding(.top, 200)
                }
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .refreshable { await vm.load() }
        .background {
            // The ember wash, as on their profile.
            PhotoBackdrop(imageName: vm.dashboard?.photoUrl ?? "home-bg", blur: 48, darken: 0.86)
        }
        // A bar of its own rather than an overlay: as an overlay the rows
        // scrolled straight through the button, and a row under it took the
        // tap. The fade gives the button a ground and lets the page pass
        // beneath. A gradient, never a blur: blur over a scroll view is
        // rendering gotcha 1.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                GlyphButton(systemName: "xmark") {
                    Haptics.tap()
                    dismiss()
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("guide-dashboard-close")
            }
            // The 44pt target's glyph sits ~13pt inside it; this lands the ×
            // on the page margin.
            .padding(.horizontal, Theme.gutter - 13)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background {
                LinearGradient(colors: [Theme.bg.opacity(0.92), Theme.bg.opacity(0.6), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
        }
        .presentationCornerRadius(0)
        // Re-read on open: the card's read may be from the morning. The
        // figures on screen stay up while it runs.
        .task { await vm.load() }
    }

    private func content(_ dashboard: GuideDashboard) -> some View {
        VStack(spacing: 0) {
            header(dashboard)
                .padding(.top, 2)

            if let failure = vm.failure {
                staleLine(failure)
                    .padding(.top, 20)
            }

            ThisMonthCard(dashboard: dashboard)
                .padding(.top, 36)

            VStack(spacing: 56) {
                audience(dashboard)
                earnings(dashboard)
                practices(dashboard)
                if !dashboard.programs.isEmpty {
                    programs(dashboard)
                }
            }
            .padding(.top, Theme.sectionGap)
        }
    }

    // MARK: Header

    private func header(_ dashboard: GuideDashboard) -> some View {
        VStack(spacing: 20) {
            AvatarView(avatarUrl: dashboard.photoUrl, name: dashboard.name,
                       seed: dashboard.instructorID, size: 76)
            VStack(spacing: 10) {
                Text("GUIDE DASHBOARD")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)
                Text(dashboard.name)
                    .font(Theme.headline(32, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.7)
                    .multilineTextAlignment(.center)
                Text("Who practiced with you, and what it earned.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .multilineTextAlignment(.center)
            }
            // On the guide's own photograph, blurred.
            .onPhoto()
        }
        .frame(maxWidth: .infinity)
    }

    /// The figures on screen are from an earlier read.
    private func staleLine(_ failure: ProfileLoadFailure) -> some View {
        HStack(spacing: 10) {
            Image(systemName: failure == .offline ? "wifi.slash" : "exclamationmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
            Text(failure == .offline ? "You're offline, so these figures may be out of date."
                                     : "We couldn't refresh these figures just now.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                Task { await vm.load() }
            } label: {
                Text("Try again")
                    .font(Theme.body(13, weight: .medium))
                    .underline()
                    .foregroundStyle(Theme.ink)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.soulPressableQuiet)
            .disabled(vm.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .soulGlassCard()
    }

    // MARK: People

    private func audience(_ dashboard: GuideDashboard) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("People")
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dashboard.totals.people.formatted())
                        .font(Theme.headline(40, weight: .light))
                        .kerning(-1)
                        .foregroundStyle(Theme.ink)
                    Text(dashboard.totals.people == 1 ? "person has practiced with you"
                                                      : "people have practiced with you")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.inkSoft)
                    Text("\(dashboard.totals.minutesHeard.formatted()) minutes of your sessions heard, all time")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 2)
                }
                // Open on the photo, not on glass.
                .onPhoto()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("guide-people-total")

                Rectangle().fill(Theme.line).frame(height: 0.5)

                PeopleByMonthChart(months: dashboard.recentMonths(6), thisMonth: dashboard.thisMonth)
            }
        }
    }

    // MARK: Earnings

    private func earnings(_ dashboard: GuideDashboard) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Past months")

            if let paid = dashboard.paidToDate {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accentSoft)
                    Text("Paid to date")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text(paid.formatted())
                        .font(Theme.body(15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
                // On the photo, not on glass.
                .onPhoto()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("guide-paid-to-date")
            }

            let past = dashboard.pastMonths
            if past.isEmpty {
                note(title: "Your first month is still running",
                     detail: "\(dashboard.thisMonth.name()) closes on \(GuideCopy.closingDate(of: dashboard.thisMonth)). Its pool, your share and what you earned will be kept here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(past) { month in
                        GuideMonthRow(month: month, thisMonth: dashboard.thisMonth)
                            .listReveal()
                    }
                    PracticeRule()
                }
            }
        }
    }

    // MARK: Practices

    private func practices(_ dashboard: GuideDashboard) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Your practices")
            if dashboard.practices.isEmpty {
                note(title: "Nobody has opened one yet",
                     detail: "Each of your practices appears here once someone opens it, with how many people it has reached.")
            } else {
                VStack(spacing: 0) {
                    ForEach(dashboard.practices) { practice in
                        GuidePracticeRow(practice: practice)
                            .listReveal()
                    }
                    PracticeRule()
                }
            }
        }
    }

    private func programs(_ dashboard: GuideDashboard) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Digital retreats")
            VStack(spacing: 0) {
                ForEach(dashboard.programs) { program in
                    HStack(spacing: 16) {
                        GuideGlyph(systemName: "leaf")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(program.title)
                                .font(Theme.headline(17))
                                .foregroundStyle(Theme.ink)
                                .kerning(-0.2)
                                .lineLimit(1)
                            Text("\(program.joined.formatted()) on it now · \(program.finished.formatted()) finished")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onPhoto()
                    .padding(.vertical, 16)
                    .overlay(alignment: .top) { PracticeRule() }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("guide-program-row")
                }
                PracticeRule()
            }
        }
    }

    // MARK: Pieces

    /// A section opens as `SectionLabel` does: a hairline across the measure
    /// and a small caps label under it.
    private func sectionTitle(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PracticeRule()
            Text(title)
                .sgEyebrow(color: Theme.ink)
                .onPhoto()
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func note(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.headline(17, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.2)
            Text(detail)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPhoto()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var unlinked: some View {
        VStack(spacing: 10) {
            Text("No guide dashboard")
                .font(Theme.headline(24, weight: .light))
                .foregroundStyle(Theme.ink)
            Text("This account isn't linked to a guide. If it should be, write to us and we'll set it up.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .multilineTextAlignment(.center)
        }
        .onPhoto()
        .padding(.horizontal, 20)
    }
}

// MARK: - This month

private struct ThisMonthCard: View {
    let dashboard: GuideDashboard

    var body: some View {
        let month = dashboard.current
        let standing = month.standing(thisMonth: dashboard.thisMonth)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(dashboard.thisMonth.name()) so far".uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(2.4)
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                StandingChip(standing: standing)
            }

            Group {
                if let amount = GuideCopy.amount(standing) {
                    Text(amount)
                } else if let share = month.share {
                    Text(GuideCopy.percent(share))
                } else {
                    Text("–")
                }
            }
            .font(Theme.headline(52, weight: .light))
            .kerning(-1.4)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.top, 14)
            .accessibilityIdentifier("guide-this-month-figure")

            Text(caption(month, standing))
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Rectangle().fill(Theme.line).frame(height: 0.5)
                .padding(.vertical, 20)

            HStack(alignment: .top, spacing: 12) {
                GuideFigure(value: month.people.formatted(), label: "People")
                GuideFigure(value: month.minutesHeard.formatted(), label: "Min heard")
                GuideFigure(value: month.completions.formatted(), label: "Finished")
            }
        }
        .padding(24)
        .soulGlassCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide-this-month")
    }

    private func caption(_ month: GuideMonth, _ standing: GuideMonth.Standing) -> String {
        let name = dashboard.thisMonth.name()
        switch standing {
        case .estimate:
            let share = month.share.map(GuideCopy.percent) ?? "0%"
            let pool = month.pool?.formatted() ?? ""
            return "An estimate: your \(share) of the minutes heard across every guide's sessions this month, from a \(pool) pool. It settles when \(name) closes."
        case .awaitingPool:
            guard month.share != nil else {
                return "No guide's sessions have been heard yet this month."
            }
            return "of the minutes heard across every guide's sessions this month were yours. What you earned appears once \(name)'s pool is set."
        case .due:
            return "\(name)'s share, waiting to be paid."
        case .paid(_, let date):
            return "Paid on \(GuideCopy.day(date))."
        }
    }
}

// MARK: - People by month

/// One column per month, oldest on the left. The selected month (this one to
/// start with) is the only bright bar and the one the figure above reads,
/// so the chart needs no axis: tap a month to read it. The table of the same
/// numbers is the Past months list below.
private struct PeopleByMonthChart: View {
    let months: [GuideMonth]
    let thisMonth: PayoutMonth

    @State private var selected: PayoutMonth?
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let plotHeight: CGFloat = 120

    private var focus: GuideMonth {
        let target = selected ?? thisMonth
        return months.first { $0.month == target } ?? .empty(target)
    }

    var body: some View {
        let peak = max(months.map(\.people).max() ?? 0, 1)

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(focus.people.formatted())
                    .font(Theme.headline(26, weight: .light))
                    .kerning(-0.6)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: Double(focus.people)))
                Text("\(focus.people == 1 ? "person" : "people") in \(focus.month.name())")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
            }
            .onPhoto()
            .animation(Theme.Motion.settle, value: focus.month)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(months) { month in
                    column(month, peak: peak)
                }
            }
            .overlay(alignment: .top) {
                // The baseline, a hairline under the bars.
                Rectangle().fill(Theme.line).frame(height: 0.5)
                    .offset(y: plotHeight)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            guard !grown else { return }
            if reduceMotion {
                grown = true
            } else {
                withAnimation(Theme.Motion.reveal.delay(0.15)) { grown = true }
            }
        }
    }

    private func column(_ month: GuideMonth, peak: Int) -> some View {
        let isFocus = month.month == focus.month
        let height = plotHeight * CGFloat(month.people) / CGFloat(peak)

        return Button {
            guard selected != month.month else { return }
            Haptics.select()
            selected = month.month
        } label: {
            VStack(spacing: 10) {
                // The whole column answers the tap, not just the bar: a quiet
                // month's bar is a sliver.
                Color.clear
                    .frame(height: plotHeight)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(isFocus ? Theme.ink : Theme.inkSoft.opacity(0.25))
                            .frame(width: 18, height: grown ? height : 0)
                            .animation(Theme.Motion.settle, value: isFocus)
                    }
                Text(month.month.shortName().uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(1.2)
                    .foregroundStyle(isFocus ? Theme.ink : Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .onPhoto()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(month.month.title())
        .accessibilityValue("\(month.people.formatted()) \(month.people == 1 ? "person" : "people")")
        .accessibilityAddTraits(isFocus ? .isSelected : [])
    }
}

// MARK: - Rows

private struct GuideMonthRow: View {
    let month: GuideMonth
    let thisMonth: PayoutMonth

    var body: some View {
        let standing = month.standing(thisMonth: thisMonth)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(month.month.title())
                    .font(Theme.headline(17))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                Text(detail)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 7) {
                Text(GuideCopy.amount(standing) ?? "–")
                    .font(Theme.body(16, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                StandingChip(standing: standing, quiet: Theme.inkSoft)
            }
        }
        // Open on the photo, not on glass.
        .onPhoto()
        .padding(.vertical, 18)
        .overlay(alignment: .top) { PracticeRule() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide-month-row")
    }

    private var detail: String {
        var parts: [String] = []
        if month.secondsHeard > 0 {
            parts.append("\(month.minutesHeard.formatted()) min heard")
            if let share = month.share { parts.append("\(GuideCopy.percent(share)) share") }
        } else {
            parts.append("No minutes heard")
        }
        parts.append("\(month.people.formatted()) \(month.people == 1 ? "person" : "people")")
        return parts.joined(separator: " · ")
    }
}

private struct GuidePracticeRow: View {
    let practice: GuidePracticeStat

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            GuideGlyph(systemName: GuideCopy.glyph(practice.kind))
            VStack(alignment: .leading, spacing: 5) {
                Text(practice.title)
                    .font(Theme.headline(17))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .lineLimit(1)
                Text(meta)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if practice.peopleThisMonth > 0 {
                    Text("+\(practice.peopleThisMonth.formatted()) this month")
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.ember)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(practice.people.formatted())
                    .font(Theme.headline(22, weight: .light))
                    .kerning(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(practice.people == 1 ? "PERSON" : "PEOPLE")
                    .font(Theme.eyebrow(9))
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        // Open on the photo, not on glass.
        .onPhoto()
        .padding(.vertical, 16)
        .overlay(alignment: .top) { PracticeRule() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide-practice-row")
    }

    private var meta: String {
        let kind = GuideCopy.kindLabel(practice.kind)
        if practice.kind == .session {
            return "\(kind) · \((practice.secondsHeard / 60).formatted()) min heard"
        }
        return "\(kind) · \(practice.completions.formatted()) finished"
    }
}

// MARK: - Small parts

/// A figure and its label, one of three in a row.
private struct GuideFigure: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.headline(22, weight: .light))
                .kerning(-0.4)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(Theme.eyebrow(9))
                .tracking(1.6)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where a month's money stands, as an icon and a word: never colour alone.
private struct StandingChip: View {
    let standing: GuideMonth.Standing
    /// The colour of "Pool not set". `muted` on glass; a row laid on the
    /// photo passes `inkSoft`, since muted sinks into a photograph.
    var quiet: Color = Theme.muted

    var body: some View {
        let (icon, text, color) = style
        Label(text, systemImage: icon)
            .font(Theme.body(11, weight: .medium))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }

    private var style: (String, String, Color) {
        switch standing {
        case .estimate:           ("chart.line.uptrend.xyaxis", "Estimate", Theme.ember)
        case .awaitingPool:       ("hourglass", "Pool not set", quiet)
        case .due:                ("clock", "To be paid", Theme.ember)
        case .paid(_, let date):  ("checkmark.seal.fill", "Paid \(GuideCopy.day(date))", Theme.accentSoft)
        }
    }
}

/// A row's kind, as a bare glyph in the margin — no disc behind it.
private struct GuideGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .light))
            .foregroundStyle(Theme.inkSoft)
            .frame(width: 28)
            .accessibilityHidden(true)
    }
}

// MARK: - Copy

/// The words and formats shared by the card and the dashboard.
enum GuideCopy {
    /// The amount a standing carries, formatted. Nil while the pool isn't set.
    static func amount(_ standing: GuideMonth.Standing) -> String? {
        switch standing {
        case .estimate(let a), .due(let a), .paid(let a, _): a.formatted()
        case .awaitingPool: nil
        }
    }

    static func amountLabel(_ standing: GuideMonth.Standing) -> String {
        switch standing {
        case .estimate:     "Est. earned"
        case .awaitingPool: "Pool not set"
        case .due:          "To be paid"
        case .paid:         "Paid"
        }
    }

    /// "12.4%".
    static func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(1)))
    }

    /// "3 Nov": a payout date, in the member's own zone.
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// "1 November" (or "November 1"): the day after the month ends, in UTC
    /// like the month itself.
    static func closingDate(of month: PayoutMonth) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = PayoutMonth.utc
        let style = Date.FormatStyle(calendar: calendar, timeZone: PayoutMonth.utc).day().month(.wide)
        return month.advanced(by: 1).start.formatted(style)
    }

    static func kindLabel(_ kind: PracticeContentKind) -> String {
        switch kind {
        case .session:  "Session"
        case .journal:  "Journal prompt"
        case .exercise: "Movement"
        case .recipe:   "Recipe"
        }
    }

    static func glyph(_ kind: PracticeContentKind) -> String {
        switch kind {
        case .session:  "waveform"
        case .journal:  "pencil.and.scribble"
        case .exercise: "figure.strengthtraining.functional"
        case .recipe:   "fork.knife"
        }
    }
}
