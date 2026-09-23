//
//  NotificationsView.swift
//  Soulfull Gatherings
//
//  Who liked your practices. Pushed from the bell on the Community tab.
//  Unread rows carry a honey dot for this visit; everything is marked read
//  once the screen has shown them, and the server latches that.
//

import SwiftUI

struct NotificationsView: View {
    @Bindable var vm: CommunityViewModel
    /// What was unread when the screen opened — kept so the dots don't vanish
    /// under the reader's eyes the moment they're marked read.
    @State private var unreadAtOpen: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PracticeBackBar(label: "Community")
                header
                content
                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background {
            PhotoBackdrop(imageName: "welcome-bg", blur: 24, darken: 0.8)
        }
        .refreshable { await vm.loadNotifications(force: true) }
        .task {
            PushRegistrar.shared.clearBadge()
            await vm.loadNotifications()
            unreadAtOpen = Set(vm.notifications.filter(\.isUnread).map(\.id))
            await vm.markAllRead()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIKES")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
            Text("Notifications")
                .font(Theme.headline(34))
                .foregroundStyle(Theme.ink)
                .kerning(-0.3)
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
                    .font(Theme.headline(20))
                    .foregroundStyle(Theme.ink)
                Text(failure.detail)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                SGPrimaryButton(title: "Try again") {
                    Task { await vm.loadNotifications(force: true) }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .soulGlassCard()
        } else if vm.notifications.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nothing yet")
                    .font(Theme.headline(20))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                Text("Finish a practice and it joins the Community feed, where people can like it. You'll hear about it here.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .soulGlassCard()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("notifications-empty")
        } else {
            VStack(spacing: 10) {
                ForEach(vm.notifications) { note in
                    row(note, unread: unreadAtOpen.contains(note.id))
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
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if unread {
                Circle()
                    .fill(Theme.honey)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .padding(.trailing, 6)
        .soulGlassCard(tint: unread ? Theme.honey.opacity(0.05) : nil,
                       stroke: unread ? Theme.honey.opacity(0.28) : Theme.glassBorder)
        .accessibilityElement(children: .ignore)
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

#Preview {
    NavigationStack {
        NotificationsView(vm: CommunityViewModel())
    }
    .preferredColorScheme(.dark)
}
