//
//  CommunityView.swift
//  Soulfull Gatherings
//
//  The Community tab: who finished what, most recent first — everyone, or
//  just your friends. One line per finished practice, with the member's face
//  beside it, grouped by the day it happened.
//
//  Browsing is open: a guest reads the whole feed. The Friends filter and the
//  Friends screen ask for an account through the same gate every practice
//  uses, and the tap is replayed once it exists. Every other member's line
//  carries Report and Block (`MemberSafety`): a guest can report, and blocking
//  goes through the gate.
//

import SwiftUI

struct CommunityView: View {
    /// Shared with `FriendsView`, which the root pushes; owned by the root.
    @Bindable var vm: CommunityViewModel
    var onOpenFriends: () -> Void = {}
    var onOpenNotifications: () -> Void = {}
    /// Switch to the You tab — where the photo beside your name is set.
    var onOpenProfile: () -> Void = {}
    /// Runs the action once an account exists, raising the sheet first if not.
    var requireAccount: (@escaping () -> Void) -> Void = { $0() }

    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    /// Read inside `body` so the observation registers.
    private let push = PushRegistrar.shared
    @State private var pushPromptDismissed = PushRegistrar.shared.promptDismissed
    @State private var reporting: ReportTarget?
    @State private var blocking: CommunityMember?

    private var isMember: Bool { auth.hasAccount || CommunityViewModel.isPreview }

    /// The one moment the app asks about notifications for likes: a member,
    /// on this tab, who has never been asked and hasn't said "not now".
    private var showsPushPrompt: Bool {
        isMember && push.status == .notDetermined && !pushPromptDismissed
    }

    /// Reload when the person behind the session changes.
    private var identity: String {
        "\(auth.userID?.uuidString ?? "none")|\(auth.hasAccount)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                controls
                if showsPushPrompt {
                    pushPrompt
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                feed
                Color.clear.frame(height: 120)
            }
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
        .refreshable { await vm.load(isMember: isMember, force: true) }
        .background {
            ZStack {
                PhotoBackdrop(imageName: "welcome-bg", blur: 24, darken: 0.78)
                AuroraBackground(speed: 0.5)
                    .opacity(0.25)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
        .task(id: identity) { await vm.load(isMember: isMember) }
        .task(id: vm.scope) { await vm.loadActivity() }
        .task(id: identity) { await push.syncIfAuthorized(isMember: auth.hasAccount) }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showsPushPrompt)
        .memberSafety(vm: vm, reporting: $reporting, blocking: $blocking,
                      isMember: isMember, requireAccount: requireAccount)
    }

    // MARK: - Push prompt

    /// Asks once, here, where a like is worth something — not at launch.
    private var pushPrompt: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "bell.badge")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.honey)
                .frame(width: 40, height: 40)
                .soulGlass(in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Hear when someone likes your practice")
                    .font(Theme.headline(16))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A quiet nudge, only for likes on what you finish.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button {
                        Haptics.bump()
                        Task { await push.requestAndRegister() }
                    } label: {
                        Text("Turn on")
                            .font(Theme.body(13, weight: .medium))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Theme.honey, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.soulPressableQuiet)
                    .accessibilityIdentifier("push-turn-on")
                    Button {
                        Haptics.tap()
                        push.promptDismissed = true
                        pushPromptDismissed = true
                    } label: {
                        Text("Not now")
                            .font(Theme.body(13, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.soulPressableQuiet)
                    .accessibilityIdentifier("push-not-now")
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .soulGlassCard(tint: Theme.honey.opacity(0.05), stroke: Theme.honey.opacity(0.28))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("push-prompt")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TOGETHER")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)
                Text("Community")
                    .font(Theme.headline(38))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
                Text("What the circle is practicing, as it happens.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onPhoto()
            Spacer(minLength: 0)
            if isMember {
                bell
                Button {
                    Haptics.tap()
                    onOpenProfile()
                } label: {
                    AvatarView(avatarUrl: settings.avatarUrl,
                               name: settings.userName,
                               seed: auth.userID?.uuidString ?? "",
                               size: 46)
                        .contentShape(Circle())
                }
                .buttonStyle(.soulPressableChip)
                .accessibilityLabel("Your profile photo")
                .accessibilityHint("Opens the You tab, where it can be changed")
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
    }

    /// Likes on your practices. The badge is the unread count.
    private var bell: some View {
        Button {
            Haptics.tap()
            onOpenNotifications()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: vm.unreadCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .symbolEffect(.bounce, value: vm.unreadCount)
                    .frame(width: 46, height: 46)
                    .soulGlass(in: Circle(), interactive: true, stroke: Theme.glassBorderHigh)
                if vm.unreadCount > 0 {
                    Text("\(vm.unreadCount)")
                        .font(Theme.body(11, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Theme.honey, in: Capsule())
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.soulPressableChip)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: vm.unreadCount)
        .accessibilityLabel(vm.unreadCount == 0 ? "Notifications" : "Notifications, \(vm.unreadCount) unread")
        .accessibilityIdentifier("community-notifications")
        .padding(.top, 4)
    }

    // MARK: - Scope toggle + friends link

    private var controls: some View {
        HStack(spacing: 10) {
            ScopeToggle(scope: $vm.scope) { chosen in
                guard chosen == .friends, !isMember else { return true }
                // A guest asked for Friends: sign in first, then land there.
                requireAccount { vm.scope = .friends }
                return false
            }

            Spacer(minLength: 0)

            Button {
                if isMember { onOpenFriends() } else { requireAccount(onOpenFriends) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                    Text("Friends")
                        .font(Theme.body(13, weight: .medium))
                    if isMember, !vm.incomingRequests.isEmpty {
                        Text("\(vm.incomingRequests.count)")
                            .font(Theme.body(11, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Theme.honey, in: Capsule())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(height: 40)
                .soulGlassCapsule(interactive: true, stroke: Theme.glassBorderHigh)
                .contentShape(Capsule())
            }
            .buttonStyle(.soulPressableChip)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: vm.incomingRequests.count)
            .accessibilityLabel(vm.incomingRequests.isEmpty
                                ? "Friends"
                                : "Friends, \(vm.incomingRequests.count) requests waiting")
            .accessibilityIdentifier("community-friends")
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Feed

    @ViewBuilder
    private var feed: some View {
        let lines = vm.activity
        // "Quiet for now" is only true once the feed has answered, not on the
        // frame before its load has even started — and the Friends feed can't
        // answer before the friends have (`isAwaitingFeed`). A refresh over
        // lines already on screen stays quiet: the spinner is for empty only.
        if vm.isAwaitingFeed && lines.isEmpty {
            ProgressView()
                .tint(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
        } else if let failure = vm.feedFailure, lines.isEmpty {
            unavailable(failure)
        } else if lines.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(dayGroups(lines), id: \.title) { group in
                    SectionLabel(title: group.title)
                    VStack(spacing: 10) {
                        ForEach(group.lines) { line in
                            ActivityRow(line: line, isSelf: line.member.id == vm.selfID,
                                        busy: vm.busy.contains(line.id)) {
                                if isMember {
                                    Task { await vm.toggleLike(line) }
                                } else {
                                    requireAccount { Task { await vm.toggleLike(line) } }
                                }
                            } onReport: {
                                reporting = ReportTarget(member: line.member, playID: line.id)
                            } onBlock: {
                                if isMember { blocking = line.member } else { requireAccount { blocking = line.member } }
                            }
                            .listReveal()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: vm.scope)
            .animation(.easeInOut(duration: 0.3), value: vm.hiddenMembers)
        }
    }

    private struct DayGroup { let title: String; let lines: [CommunityActivity] }

    /// Today · Yesterday · Earlier. Finer than that (last Tuesday, two weeks
    /// ago) is more calendar than a feed of other people's mornings wants.
    private func dayGroups(_ lines: [CommunityActivity]) -> [DayGroup] {
        let calendar = Calendar.current
        var today: [CommunityActivity] = [], yesterday: [CommunityActivity] = [], earlier: [CommunityActivity] = []
        for line in lines {
            if calendar.isDateInToday(line.completedAt) { today.append(line) }
            else if calendar.isDateInYesterday(line.completedAt) { yesterday.append(line) }
            else { earlier.append(line) }
        }
        return [DayGroup(title: "Today", lines: today),
                DayGroup(title: "Yesterday", lines: yesterday),
                DayGroup(title: "Earlier", lines: earlier)]
            .filter { !$0.lines.isEmpty }
    }

    // MARK: - Empty / failure

    @ViewBuilder
    private var emptyState: some View {
        switch vm.scope {
        case .all:
            emptyCard(title: "Quiet for now",
                      detail: "Finish a practice and you'll be the first line here. Everyone's finished sessions, movement and recipes gather in this feed.")
        case .friends where vm.friends.isEmpty:
            // Through the gate like the Friends button: the Friends screen is
            // personal, whichever way it's reached.
            emptyCard(title: "Practice alongside people you know",
                      detail: "Add the people you practice with, and what they finish will gather here — and yours with them.",
                      action: "Find friends") {
                if isMember { onOpenFriends() } else { requireAccount(onOpenFriends) }
            }
        case .friends:
            emptyCard(title: "Nothing from your friends yet",
                      detail: "When someone you know finishes a practice, it shows up here.")
        }
    }

    private func emptyCard(title: String, detail: String,
                           action: String? = nil, perform: @escaping () -> Void = {}) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.headline(20))
                .foregroundStyle(Theme.ink)
                .kerning(-0.2)
            Text(detail)
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button {
                    perform()
                } label: {
                    HStack(spacing: 6) {
                        Text(action)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.honey)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.soulPressableQuiet)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .soulGlassCard()
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("community-empty")
    }

    private func unavailable(_ failure: CommunityLoadFailure) -> some View {
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
                Task { await vm.load(isMember: isMember, force: true) }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .soulGlassCard()
        .padding(.horizontal, 20)
    }
}

// MARK: - Scope toggle

/// All | Friends on one glass capsule, a cream lens sliding behind the chosen
/// one — the bottom nav's physics at chip scale. `shouldSwitch` lets the host
/// intercept a choice (a guest choosing Friends) before it lands.
private struct ScopeToggle: View {
    @Binding var scope: CommunityScope
    var shouldSwitch: (CommunityScope) -> Bool = { _ in true }
    @Namespace private var lens

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CommunityScope.allCases) { option in
                let active = scope == option
                Button {
                    guard option != scope, shouldSwitch(option) else { return }
                    Haptics.select()
                    scope = option
                } label: {
                    Text(option.label)
                        .font(Theme.body(13, weight: .medium))
                        .tracking(0.3)
                        .foregroundStyle(active ? Color.black : Theme.ink.opacity(0.85))
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background {
                            if active {
                                Capsule()
                                    .fill(Theme.ink)
                                    .matchedGeometryEffect(id: "lens", in: lens)
                                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(SoulPressableStyle(scale: 0.94, hapticOnPress: false, dim: false))
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(active ? .isSelected : [])
                .accessibilityIdentifier("community-scope-\(option.rawValue)")
            }
        }
        .padding(3)
        .soulGlassCapsule(interactive: true, stroke: Theme.glassBorderHigh)
        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: scope)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show activity from")
    }
}

// MARK: - Activity row

/// "Hugo D. practiced Confidence Boost", a face beside it, the track and the
/// time beneath. Someone else's line ends in their like button and "⋯"
/// (Report, Block).
private struct ActivityRow: View {
    let line: CommunityActivity
    let isSelf: Bool
    var busy = false
    var onLike: () -> Void = {}
    var onReport: () -> Void = {}
    var onBlock: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AvatarView(avatarUrl: line.member.avatarUrl,
                       name: line.member.displayName,
                       seed: line.member.id.uuidString,
                       size: 46)

            VStack(alignment: .leading, spacing: 5) {
                sentence
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(line.kindLabel) · \(Self.relative(line.completedAt))".uppercased())
                    .font(Theme.eyebrow(10))
                    .tracking(1.6)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelf {
                // Your own line: the count, if anyone has, and no button.
                if line.likeCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .medium))
                        Text("\(line.likeCount)")
                            .font(Theme.body(12, weight: .medium))
                    }
                    .foregroundStyle(Theme.honey)
                    .accessibilityHidden(true)
                }
            } else {
                LikeButton(count: line.likeCount, liked: line.likedByMe, busy: busy, action: onLike)
                MemberSafetyMenu(member: line.member, onReport: onReport, onBlock: onBlock)
                    .padding(.leading, -4)
            }
        }
        .padding(12)
        .padding(.trailing, isSelf ? 6 : 0)
        .soulGlassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("activity-row")
    }

    private var spoken: String {
        var s = "\(isSelf ? "You" : line.member.displayName) practiced \(line.title). \(line.kindLabel), \(Self.relative(line.completedAt))"
        if line.likeCount > 0 { s += ". \(line.likeCount == 1 ? "1 like" : "\(line.likeCount) likes")" }
        return s
    }

    /// Name and title in ink, the verb between them quieter — one line that
    /// reads as a sentence rather than three fields.
    private var sentence: Text {
        Text(isSelf ? "You" : line.member.displayName)
            .font(Theme.body(15, weight: .medium))
            .foregroundStyle(Theme.ink)
        + Text(" practiced ")
        + Text(line.title)
            .font(Theme.body(15, weight: .medium))
            .foregroundStyle(Theme.ink)
    }

    /// "just now", "12 min ago", "3 hr ago", "yesterday", "Monday", "12 Sep".
    static func relative(_ date: Date) -> String {
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

// MARK: - Like button

/// A heart and a count. Fills honey and bounces when it's yours; the count
/// rolls rather than snaps. One tap toggles.
private struct LikeButton: View {
    let count: Int
    let liked: Bool
    var busy = false
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .medium))
                    .symbolEffect(.bounce.up, value: liked)
                    .contentTransition(.symbolEffect(.replace))
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.body(12, weight: .medium))
                        .contentTransition(.numericText(value: Double(count)))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(liked ? Theme.honey : Theme.inkSoft)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .soulGlassCapsule(tint: liked ? Theme.honey.opacity(0.10) : nil, interactive: true,
                              stroke: liked ? Theme.honey.opacity(0.35) : Theme.glassBorder)
            .contentShape(Capsule())
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: liked)
            .animation(.easeOut(duration: 0.25), value: count)
        }
        .buttonStyle(SoulPressableStyle(scale: 0.88, hapticOnPress: false))
        .disabled(busy)
        .accessibilityLabel(liked ? "Unlike" : "Like")
        .accessibilityValue(count == 1 ? "1 like" : "\(count) likes")
        .accessibilityIdentifier("like-button")
    }
}

#Preview {
    let a = AppState()
    return CommunityView(vm: CommunityViewModel())
        .environment(a.auth)
        .environment(a.settings)
        .preferredColorScheme(.dark)
}
