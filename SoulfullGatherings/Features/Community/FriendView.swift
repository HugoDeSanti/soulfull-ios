//
//  FriendView.swift
//  Soulfull Gatherings
//
//  A friend's page: their face and name, then their practice in the four
//  figures they see on their own You tab (streak, best streak, classes,
//  minutes). Pushed from a friend's row on the Friends screen.
//
//  Numbers only (0034): never which practices and never a calendar; what they
//  finished is in the Friends feed already. A friend with "Share my practice"
//  off keeps their numbers to themselves, and the page says so. Report and
//  Block are the "⋯" by their face; Remove friend is at the foot of the page.
//  The page closes itself once they're no longer a friend: removed here,
//  blocked, or gone from elsewhere.
//

import SwiftUI

struct FriendView: View {
    @Bindable var vm: CommunityViewModel
    let member: CommunityMember

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemove = false
    @State private var reporting: ReportTarget?
    @State private var blocking: CommunityMember?
    /// Read inside `body`, so a streak moves at midnight.
    private let clock = AppClock.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PracticeBackBar(label: "Friends")
                header
                    .padding(.top, 28)
                practiceSection
                    .padding(.top, Theme.headerGap)
                removeButton
                    .padding(.top, Theme.sectionGap)
                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .statusBarFade()
        .background { PhotoBackdrop(imageName: "welcome-bg", blur: 24, darken: 0.8) }
        .refreshable { await vm.loadFriendPractice(force: true) }
        .task { await vm.loadFriendPractice() }
        .onChange(of: vm.standing(for: member.id)) { _, standing in
            if standing != .friends { dismiss() }
        }
        .confirmationDialog("Remove \(member.displayName)?", isPresented: $confirmingRemove,
                            titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) {
                guard let row = vm.friends.first(where: { $0.otherID == member.id }) else { return }
                Task { await vm.remove(row) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop seeing each other's practices in your Friends feeds, and each other's numbers. They won't be told.")
        }
        // Only a member has friends.
        .memberSafety(vm: vm, reporting: $reporting, blocking: $blocking,
                      isMember: true, requireAccount: { $0() })
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                AvatarView(avatarUrl: member.avatarUrl, name: member.displayName,
                           seed: member.id.uuidString, size: 64)
                Spacer(minLength: 0)
                MemberSafetyMenu(member: member,
                                 onReport: { reporting = ReportTarget(member: member) },
                                 onBlock: { blocking = member })
                    .padding(.trailing, -13)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("FRIEND")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)
                Text(member.displayName)
                    .font(Theme.headline(34, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.7)
                    .lineLimit(2)
                    .accessibilityIdentifier("friend-name")
                Text(subline)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onPhoto()
        }
    }

    private var subline: String {
        if case .keptPrivate = vm.practice(of: member.id) {
            return "They keep their practice to themselves."
        }
        return "Their practice, in the numbers they see on their own You tab."
    }

    // MARK: - Their practice

    @ViewBuilder
    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionLabel(title: "Their practice")
                .padding(.horizontal, -Theme.gutter)
                .onPhoto()

            switch vm.practice(of: member.id) {
            case .loading:
                table(nil)
            case .shared(let practice):
                table(practice)
            case .keptPrivate:
                Text("Nothing to show while \(member.displayName) keeps “Share my practice” off.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .onPhoto()
                    .accessibilityIdentifier("friend-practice-private")
            case .unavailable(let failure):
                unavailable(failure)
            }
        }
        .animation(Theme.Motion.settle, value: vm.practice(of: member.id))
    }

    /// Open numerals on the page, two rows of two with a rule between, as on
    /// the You tab. Dashes until the numbers are in.
    private func table(_ practice: FriendPractice?) -> some View {
        let now = clock.now
        let streak = practice?.streak(now: now)
        return Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 24) {
            GridRow {
                StatTile(value: streak?.current,
                         label: "Day streak",
                         caption: practice.map { $0.lastPracticedLabel(now: now) ?? "No practices finished yet" } ?? " ",
                         systemImage: "flame.fill",
                         accent: (streak?.current ?? 0) > 0,
                         breathes: streak?.keptToday ?? false,
                         spoken: "Current streak",
                         spokenValue: streak.map { days($0.current) })
                    .accessibilityIdentifier("friend-stat-current-streak")
                StatTile(value: streak?.best,
                         label: "Best streak",
                         caption: streak.map(bestCaption) ?? " ",
                         systemImage: "laurel.leading",
                         spoken: "Best streak",
                         spokenValue: streak.map { days($0.best) })
                    .accessibilityIdentifier("friend-stat-best-streak")
            }
            Rectangle()
                .fill(Theme.line)
                .frame(height: 0.5)
                .accessibilityHidden(true)
            GridRow {
                StatTile(value: practice?.classesTaken,
                         label: "Classes taken",
                         caption: "Sessions & movement",
                         systemImage: "figure.mind.and.body",
                         spoken: "Classes taken",
                         spokenValue: practice.map { "\($0.classesTaken)" })
                    .accessibilityIdentifier("friend-stat-classes")
                StatTile(value: practice?.minutesPracticed,
                         label: "Minutes practiced",
                         caption: minutesCaption(practice),
                         systemImage: "hourglass",
                         spoken: "Minutes practiced",
                         spokenValue: practice.map { "\($0.minutesPracticed)" })
                    .accessibilityIdentifier("friend-stat-minutes")
            }
        }
    }

    private func bestCaption(_ streak: PracticeStreak) -> String {
        streak.best > 1 && streak.best == streak.current ? "They're on it now" : "Days in a row"
    }

    private func minutesCaption(_ practice: FriendPractice?) -> String {
        guard let minutes = practice?.minutesPracticed, minutes >= 60 else { return "Time in class" }
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    private func unavailable(_ failure: CommunityLoadFailure) -> some View {
        HStack(spacing: 10) {
            Image(systemName: failure == .offline ? "wifi.slash" : "exclamationmark.circle")
                .font(.system(size: 13, weight: .medium))
            Text(failure == .offline ? "You're offline. Reconnect to see their practice."
                                     : "We couldn't load their practice just now.")
                .font(Theme.body(13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                Task { await vm.loadFriendPractice(force: true) }
            } label: {
                Text("Try again")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.ember)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.soulPressableQuiet)
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .soulGlass(in: Theme.controlShape)
    }

    // MARK: - Remove

    private var removeButton: some View {
        Button {
            Haptics.tap()
            confirmingRemove = true
        } label: {
            Text("Remove friend")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .onPhoto()
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                // The whole row, not just the letters (rendering gotcha 5).
                .contentShape(Rectangle())
        }
        .buttonStyle(.soulPressableQuiet)
        .accessibilityIdentifier("friend-remove")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        FriendView(vm: CommunityViewModel(),
                   member: CommunityMember(id: UUID(), displayName: "Alma G.", avatarUrl: nil))
    }
    .preferredColorScheme(.dark)
}
#endif
