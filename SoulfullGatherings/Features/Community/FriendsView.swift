//
//  FriendsView.swift
//  Soulfull Gatherings
//
//  Finding and keeping friends: search members by name, answer the requests
//  waiting on you, see the ones you've sent, and the friends you have, each
//  with their streak and classes under their name. A friend's row opens their
//  page (`FriendView`), where they can be removed.
//
//  Pushed from the Community tab behind the account gate; the server refuses
//  a guest anyway. Search matches on the full name server-side and answers
//  with the abbreviated one, so a surname finds someone without ever being
//  shown. There is no search by email, on purpose. Every row carries Report
//  and Block (`MemberSafety`). A request sent within 30 days of the last one
//  to the same person being declined is refused, and the banner says why.
//

import SwiftUI

struct FriendsView: View {
    @Bindable var vm: CommunityViewModel
    /// Push a friend's page.
    var onOpenFriend: (CommunityMember) -> Void = { _ in }
    @State private var reporting: ReportTarget?
    @State private var blocking: CommunityMember?
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                PracticeBackBar(label: "Community")
                header
                searchField
                if let error = vm.actionError {
                    errorBanner(error)
                }
                if vm.searchQuery.trimmingCharacters(in: .whitespaces).count >= 2 {
                    results
                }
                if !vm.incomingRequests.isEmpty {
                    section("Requests", rows: vm.incomingRequests) { row in
                        pill("Accept", filled: true) { Task { await vm.accept(row) } }
                        pill("Decline") { Task { await vm.remove(row) } }
                    }
                    .accessibilityIdentifier("friends-requests")
                }
                if !vm.outgoingRequests.isEmpty {
                    section("Sent", rows: vm.outgoingRequests) { row in
                        pill("Withdraw") { Task { await vm.remove(row) } }
                    }
                }
                friendsSection
                Color.clear.frame(height: 120)
            }
            .padding(.top, 8)
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .statusBarFade()
        .scrollDismissesKeyboard(.interactively)
        .background { PhotoBackdrop(imageName: "welcome-bg", blur: 24, darken: 0.8) }
        .refreshable {
            await vm.loadFriendships(force: true)
            await vm.loadFriendPractice(force: true)
        }
        .task {
            await vm.loadFriendships()
            await vm.loadFriendPractice()
        }
        // A request accepted here: the new friend's numbers.
        .onChange(of: vm.friendIDs) { Task { await vm.loadFriendPractice() } }
        // The Friends screen is behind the gate already: everyone here is a member.
        .memberSafety(vm: vm, reporting: $reporting, blocking: $blocking,
                      isMember: true, requireAccount: { $0() })
    }

    // MARK: - Header + search

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FRIENDS")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
            Text("Your people")
                .font(Theme.headline(34, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.7)
            Text("Find the people you practice with. What they finish joins your Friends feed, and what you finish joins theirs.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPhoto()
    }

    /// UIKit-backed field, so no `.onPhoto()` or blur on this container (gotcha #1).
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
            TextField("", text: $vm.searchQuery,
                      prompt: Text("Search members by name").foregroundStyle(Theme.muted))
                .font(Theme.body(15))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .accessibilityIdentifier("friends-search")
            if !vm.searchQuery.isEmpty {
                Button {
                    Haptics.tap()
                    vm.searchQuery = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.soulPressable)
                .padding(.trailing, -12)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .soulGlass(in: Theme.controlShape, stroke: searchFocused ? Theme.glassBorderHigh : Theme.glassBorder)
        .animation(Theme.Motion.settle, value: searchFocused)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: "Results")
                .padding(.horizontal, -Theme.gutter)
                .onPhoto()
            if vm.isSearching && vm.searchResults.isEmpty {
                ProgressView()
                    .tint(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else if let failure = vm.searchFailure, vm.searchResults.isEmpty {
                // Not "No one by that name yet": the directory never answered.
                HStack(spacing: 10) {
                    Image(systemName: failure == .offline ? "wifi.slash" : "exclamationmark.circle")
                        .font(.system(size: 13, weight: .medium))
                    Text(failure == .offline
                         ? "You're offline. Reconnect to search for members."
                         : "Search isn't working at our end just now.")
                        .font(Theme.body(13))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button {
                        vm.retrySearch()
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
                .padding(.top, 10)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("search-failure")
            } else if vm.searchResults.isEmpty {
                Text("No one by that name yet. Names match what people entered when they joined.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .onPhoto()
                    .padding(.top, 10)
            } else {
                ForEach(vm.searchResults) { member in
                    MemberRow(member: member, ruled: member.id != vm.searchResults.first?.id) {
                        standingControl(for: member)
                        safetyMenu(for: member)
                    }
                    .accessibilityIdentifier("search-result")
                }
            }
        }
    }

    /// The one control beside a found member, by where we stand.
    @ViewBuilder
    private func standingControl(for member: CommunityMember) -> some View {
        switch vm.standing(for: member.id) {
        case .none:
            pill("Add", filled: true, busy: vm.busy.contains(member.id)) {
                Task { await vm.sendRequest(to: member) }
            }
            .accessibilityIdentifier("add-friend")
        case .requested:
            chip("Requested", systemImage: "clock")
        case .awaitingMyAnswer:
            if let row = vm.friendships.first(where: { $0.otherID == member.id }) {
                pill("Accept", filled: true) { Task { await vm.accept(row) } }
            }
        case .friends:
            chip("Friends", systemImage: "checkmark")
        }
    }

    // MARK: - Sections

    private func section<Controls: View>(_ title: String, rows: [Friendship],
                                         @ViewBuilder controls: @escaping (Friendship) -> Controls) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: title)
                .padding(.horizontal, -Theme.gutter)
                .onPhoto()
            ForEach(rows) { row in
                let member = row.other ?? CommunityMember(id: row.otherID, displayName: "A member", avatarUrl: nil)
                MemberRow(member: member, ruled: row.id != rows.first?.id) {
                    HStack(spacing: 8) { controls(row) }
                    safetyMenu(for: member)
                }
                .listReveal()
            }
        }
    }

    @ViewBuilder
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: "Friends")
                .padding(.horizontal, -Theme.gutter)
                .onPhoto()
            if let failure = vm.friendshipsFailure, vm.friendships.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: failure == .offline ? "wifi.slash" : "exclamationmark.circle")
                        .font(.system(size: 13, weight: .medium))
                    Text(failure == .offline ? "You're offline. Reconnect to see your friends."
                                             : "We couldn't load your friends just now.")
                        .font(Theme.body(13))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button {
                        Task { await vm.loadFriendships(force: true) }
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
                .padding(.top, 10)
            } else if vm.friends.isEmpty {
                Text(vm.friendshipsLoaded
                     ? "No friends yet. Search for someone above to send the first request."
                     : " ")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .onPhoto()
                    .padding(.top, 10)
            } else {
                ForEach(vm.friends) { row in
                    let member = row.other ?? CommunityMember(id: row.otherID, displayName: "A member", avatarUrl: nil)
                    MemberRow(member: member, ruled: row.id != vm.friends.first?.id,
                              practice: vm.practice(of: member.id),
                              onOpen: { onOpenFriend(member) }) {
                        safetyMenu(for: member)
                    }
                    .listReveal()
                }
            }
        }
    }

    // MARK: - Small controls

    private func safetyMenu(for member: CommunityMember) -> some View {
        MemberSafetyMenu(member: member,
                         onReport: { reporting = ReportTarget(member: member) },
                         onBlock: { blocking = member })
            .padding(.leading, -8)
            .padding(.trailing, -10)
    }

    /// A small button: filled ink for the action a row is waiting on (Add,
    /// Accept), an ink hairline for the rest.
    private func pill(_ title: String, filled: Bool = false, busy: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button {
            Haptics.bump()
            action()
        } label: {
            Text(title)
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(filled ? Color.black : Theme.ink)
                // Its own width, always: beside a name that takes the rest
                // of the row, two buttons were squeezed until
                // "Accept" broke in half.
                .lineLimit(1)
                .fixedSize()
                // An outlined label sits on the photo; a filled one has its
                // own ground, where a halo would only smudge black type.
                .modifier(OnPhotoUnlessFilled(filled: filled))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background {
                    if filled {
                        Theme.controlShape.fill(Theme.ink)
                    } else {
                        Theme.controlShape.strokeBorder(Theme.ink.opacity(0.7), lineWidth: Theme.hairline)
                    }
                }
                // A 44pt target around the 34pt block.
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .opacity(busy ? 0.5 : 1)
        }
        .buttonStyle(.soulPressableQuiet)
        .disabled(busy)
    }

    /// Where you stand with someone, said quietly beside their name: no box.
    private func chip(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .regular))
            // Caps for the eye only: the label stays "Requested".
            Text(title)
                .font(Theme.eyebrow(10))
                .tracking(1.6)
                .textCase(.uppercase)
        }
        .foregroundStyle(Theme.inkSoft)
        .onPhoto()
        .frame(height: 44)
        .accessibilityElement(children: .combine)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .medium))
            Text(message)
                .font(Theme.body(13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .soulGlass(in: Theme.controlShape, stroke: Theme.ember.opacity(0.35))
        .transition(.opacity)
    }
}

/// A face, a name, and whatever control the section puts beside them — an
/// open row on the photo, with a hairline above it when `ruled` (every row
/// but a section's first). A friend's row adds their practice in a line under
/// the name, and opens their page from the face and the name.
private struct MemberRow<Trailing: View>: View {
    let member: CommunityMember
    var ruled = false
    /// A friend's numbers, for the line under the name.
    var practice: FriendPracticeStanding? = nil
    /// Opens their page. The face and the name become the button; the
    /// controls beside them stay their own.
    var onOpen: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    /// Read inside `body`, so a streak moves at midnight.
    private let clock = AppClock.shared

    var body: some View {
        HStack(spacing: 12) {
            if let onOpen {
                Button(action: onOpen) {
                    identity(opens: true)
                }
                .buttonStyle(.soulPressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenIdentity)
                .accessibilityHint("Opens their page")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("friend-row")
            } else {
                identity(opens: false)
            }
            trailing
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            if ruled {
                Rectangle().fill(Theme.line).frame(height: 0.5)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(member.displayName)
    }

    private func identity(opens: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarView(avatarUrl: member.avatarUrl, name: member.displayName,
                       seed: member.id.uuidString, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.displayName)
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let practice {
                    FriendPracticeLine(standing: practice, now: clock.now)
                }
            }
            .onPhoto()
            .frame(maxWidth: .infinity, alignment: .leading)
            if opens {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.inkSoft)
                    .onPhoto()
            }
        }
        // The whole block answers a tap, gaps included (rendering gotcha 5).
        .contentShape(Rectangle())
    }

    private var spokenIdentity: String {
        guard let practice else { return member.displayName }
        switch practice {
        case .shared(let numbers): return "\(member.displayName), \(numbers.summary(now: clock.now))"
        case .keptPrivate:         return "\(member.displayName), keeps their practice private"
        case .loading, .unavailable: return member.displayName
        }
    }
}

/// The line under a friend's name: their streak and classes, or that they
/// keep them private. Held open while it loads, so the row doesn't grow as the
/// numbers arrive; a read that failed leaves it blank (the friend's page
/// says why).
private struct FriendPracticeLine: View {
    let standing: FriendPracticeStanding
    let now: Date

    var body: some View {
        HStack(spacing: 5) {
            switch standing {
            case .shared(let practice):
                // The one warm mark, as on the You tab: a streak that's alive.
                if practice.streak(now: now).current > 0 {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(Theme.ember)
                }
                Text(practice.summary(now: now))
            case .keptPrivate:
                Text("Keeps their practice private")
            case .loading, .unavailable:
                Text(" ")
            }
        }
        .font(Theme.body(12))
        .foregroundStyle(Theme.inkSoft)
        .lineLimit(1)
        .animation(Theme.Motion.settle, value: standing)
    }
}

/// `.onPhoto()` for an outlined button's label only.
private struct OnPhotoUnlessFilled: ViewModifier {
    let filled: Bool

    func body(content: Content) -> some View {
        if filled { content } else { content.onPhoto() }
    }
}

#Preview {
    NavigationStack {
        FriendsView(vm: CommunityViewModel())
    }
    .preferredColorScheme(.dark)
}
