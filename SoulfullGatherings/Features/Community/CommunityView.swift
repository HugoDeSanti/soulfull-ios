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
//  uses, and the tap is replayed once it exists.
//

import SwiftUI

struct CommunityView: View {
    /// Shared with `FriendsView`, which the root pushes; owned by the root.
    @Bindable var vm: CommunityViewModel
    var onOpenFriends: () -> Void = {}
    /// Switch to the You tab — where the photo beside your name is set.
    var onOpenProfile: () -> Void = {}
    /// Runs the action once an account exists, raising the sheet first if not.
    var requireAccount: (@escaping () -> Void) -> Void = { $0() }

    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings

    private var isMember: Bool { auth.hasAccount || CommunityViewModel.isPreview }

    /// Reload when the person behind the session changes.
    private var identity: String {
        "\(auth.userID?.uuidString ?? "none")|\(auth.hasAccount)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                controls
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
                Text("What the circle is practising, as it happens.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onPhoto()
            Spacer(minLength: 0)
            if isMember {
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
        if vm.isLoadingActivity && lines.isEmpty {
            ProgressView()
                .tint(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
        } else if let failure = vm.activityFailure, lines.isEmpty {
            unavailable(failure)
        } else if lines.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(dayGroups(lines), id: \.title) { group in
                    SectionLabel(title: group.title)
                    VStack(spacing: 10) {
                        ForEach(group.lines) { line in
                            ActivityRow(line: line, isSelf: line.member.id == vm.selfID)
                                .listReveal()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: vm.scope)
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
            emptyCard(title: "Practice alongside people you know",
                      detail: "Add the people you practise with, and what they finish will gather here — and yours with them.",
                      action: "Find friends", perform: onOpenFriends)
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
/// time beneath.
private struct ActivityRow: View {
    let line: CommunityActivity
    let isSelf: Bool

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
        }
        .padding(12)
        .padding(.trailing, 6)
        .soulGlassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isSelf ? "You" : line.member.displayName) practiced \(line.title). \(line.kindLabel), \(Self.relative(line.completedAt))")
        .accessibilityIdentifier("activity-row")
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

#Preview {
    let a = AppState()
    return CommunityView(vm: CommunityViewModel())
        .environment(a.auth)
        .environment(a.settings)
        .preferredColorScheme(.dark)
}
