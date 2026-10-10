//
//  NotificationsView.swift
//  Soulfull Gatherings
//
//  Who liked your practices. Pushed from the bell on the Community tab, or by
//  a tapped like push. Unread rows carry an ember dot for this visit; each is
//  marked read once the screen has shown it — by id, so a like that lands
//  later stays unread until it too is on screen — and the server latches that.
//

import SwiftUI

struct NotificationsView: View {
    @Bindable var vm: CommunityViewModel
    /// Everything that was unread when this screen showed it — kept so the
    /// dots don't vanish under the reader's eyes the moment they're marked
    /// read. Grows when a refresh (or a like push while the screen is open)
    /// brings in more.
    @State private var unreadAtOpen: Set<UUID> = []
    @State private var reporting: ReportTarget?
    @State private var blocking: CommunityMember?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                PracticeBackBar(label: "Community")
                header
                content
                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .statusBarScrim()
        .background { PhotoBackdrop(imageName: "welcome-bg", blur: 24, darken: 0.8) }
        .refreshable { await vm.loadNotifications(force: true) }
        .task {
            PushRegistrar.shared.clearBadge()
            // Forced: opening this screen is asking what's new, and the list
            // the bell counted from may be minutes old.
            await vm.loadNotifications(force: true)
            // Whether or not that read worked — what's on screen has been seen.
            markShownRead()
        }
        // A refresh, or a reload for a like push tapped while this screen is
        // already open, can bring in rows the task above never saw.
        .onChange(of: vm.notifications) { markShownRead() }
        // Pushed from the bell, which only a member sees.
        .memberSafety(vm: vm, reporting: $reporting, blocking: $blocking,
                      isMember: true, requireAccount: { $0() })
    }

    /// Marks read what is unread on screen now, keeping its dot for this visit.
    /// Only those ids: anything that arrives later is marked when it shows.
    private func markShownRead() {
        let shown = Set(vm.notifications.filter(\.isUnread).map(\.id))
        guard !shown.isEmpty else { return }
        unreadAtOpen.formUnion(shown)
        Task { await vm.markRead(shown) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIKES")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
            Text("Notifications")
                .font(Theme.headline(34, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.7)
            Text("When someone likes a practice you finished, it lands here.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPhoto()
    }

    @ViewBuilder
    private var content: some View {
        if !vm.notificationsLoaded && vm.notifications.isEmpty && vm.notificationsFailure == nil {
            ProgressView()
                .tint(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if let failure = vm.notificationsFailure, vm.notifications.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(failure.title)
                    .font(Theme.headline(22, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
                Text(failure.detail)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                SGPrimaryButton(title: "Try again") {
                    Task { await vm.loadNotifications(force: true) }
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onPhoto()
            .padding(.top, 22)
            .overlay(alignment: .top) { Hairline() }
        } else if vm.notifications.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nothing yet")
                    .font(Theme.headline(22, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
                Text("Finish a practice and it joins the Community feed, where people can like it. You'll hear about it here.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onPhoto()
            .padding(.top, 22)
            .overlay(alignment: .top) { Hairline() }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("notifications-empty")
        } else {
            // Open rows on the photo, ruled above and between.
            VStack(spacing: 0) {
                ForEach(vm.notifications) { note in
                    row(note, unread: unreadAtOpen.contains(note.id))
                        .overlay(alignment: .top) { Hairline() }
                        .listReveal()
                }
            }
        }
    }

    private func row(_ note: LikeNotification, unread: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarView(avatarUrl: note.actor?.avatarUrl,
                       name: note.actor?.displayName ?? "?",
                       seed: note.actor?.id.uuidString ?? "gone",
                       size: 44)
            VStack(alignment: .leading, spacing: 5) {
                sentence(note)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(relative(note.createdAt).uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkSoft)
            }
            .onPhoto()
            .frame(maxWidth: .infinity, alignment: .leading)
            if unread {
                Circle()
                    .fill(Theme.ember)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            if let actor = note.actor {
                MemberSafetyMenu(member: actor,
                                 onReport: { reporting = ReportTarget(member: actor, playID: note.playID) },
                                 onBlock: { blocking = actor })
                    .padding(.leading, -8)
                    .padding(.trailing, -10)
            }
        }
        .padding(.vertical, 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(note.actor?.displayName ?? "Someone") liked your \(note.practiceTitle ?? "practice") practice, \(relative(note.createdAt))\(unread ? ", new" : "")")
        .accessibilityIdentifier("notification-row")
    }

    private func sentence(_ note: LikeNotification) -> Text {
        Text(note.actor?.displayName ?? "Someone")
            .font(Theme.body(15, weight: .medium))
            .foregroundStyle(Theme.ink)
        + Text(" liked your ")
        + Text(note.practiceTitle ?? "practice")
            .font(Theme.body(15, weight: .medium))
            .foregroundStyle(Theme.ink)
        + Text(note.practiceTitle == nil ? "" : " practice")
    }

    private func relative(_ date: Date) -> String {
        let seconds = max(0, Date.now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "\(Int(seconds / 3600)) hr ago" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: .now)).day ?? 0
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// The rule above a row and an open block.
private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        NotificationsView(vm: CommunityViewModel())
    }
    .preferredColorScheme(.dark)
}
