//
//  FriendsView.swift
//  Soulfull Gatherings
//
//  Finding and keeping friends: search members by name, answer the requests
//  waiting on you, see the ones you've sent, and the friends you have.
//
//  Pushed from the Community tab behind the account gate; the server refuses
//  a guest anyway. Search matches on the full name server-side and answers
//  with the abbreviated one, so a surname finds someone without ever being
//  shown. There is no search by email, on purpose.
//

import SwiftUI

struct FriendsView: View {
    @Bindable var vm: CommunityViewModel
    @State private var removing: Friendship?
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
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
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background {
            PhotoBackdrop(imageName: "welcome-bg", blur: 24, darken: 0.8)
        }
        .refreshable { await vm.loadFriendships(force: true) }
        .task { await vm.loadFriendships() }
        .confirmationDialog("Remove \(removing?.other?.displayName ?? "this friend")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) {
                if let row = removing { Task { await vm.remove(row) } }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("You'll stop seeing each other's practices in your Friends feeds. They won't be told.")
        }
    }

    // MARK: - Header + search

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FRIENDS")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
            Text("Your people")
                .font(Theme.headline(34))
                .foregroundStyle(Theme.ink)
                .kerning(-0.3)
            Text("Find the people you practise with. What they finish joins your Friends feed, and what you finish joins theirs.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPhoto()
    }

    /// UIKit-backed field, so no `.onPhoto()` on this container (gotcha #1).
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
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.soulPressableChip)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .soulGlassCard(radius: 16, stroke: searchFocused ? Theme.glassBorderHigh : Theme.glassBorder)
        .animation(.easeOut(duration: 0.2), value: searchFocused)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Results")
                .padding(.horizontal, -20)
            if vm.isSearching && vm.searchResults.isEmpty {
                ProgressView()
                    .tint(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else if vm.searchResults.isEmpty {
                Text("No one by that name yet. Names match what people entered when they joined.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            } else {
                ForEach(vm.searchResults) { member in
                    MemberRow(member: member) {
                        standingControl(for: member)
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
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: title)
                .padding(.horizontal, -20)
            ForEach(rows) { row in
                MemberRow(member: row.other ?? CommunityMember(id: row.otherID, displayName: "A member", avatarUrl: nil)) {
                    HStack(spacing: 8) { controls(row) }
                }
                .listReveal()
            }
        }
    }

    @ViewBuilder
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Friends")
                .padding(.horizontal, -20)
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
                            .foregroundStyle(Theme.honey)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.soulPressableQuiet)
                }
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .soulGlassCard()
            } else if vm.friends.isEmpty {
                Text(vm.friendshipsLoaded
                     ? "No friends yet. Search for someone above to send the first request."
                     : " ")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            } else {
                ForEach(vm.friends) { row in
                    MemberRow(member: row.other ?? CommunityMember(id: row.otherID, displayName: "A member", avatarUrl: nil)) {
                        pill("Remove") { removing = row }
                    }
                    .accessibilityIdentifier("friend-row")
                    .listReveal()
                }
            }
        }
    }

    // MARK: - Small controls

    private func pill(_ title: String, filled: Bool = false, busy: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button {
            Haptics.bump()
            action()
        } label: {
            Text(title)
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(filled ? Color.black : Theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background {
                    if filled {
                        Capsule().fill(Theme.honey)
                    }
                }
                .modifier(QuietGlassIfNeeded(enabled: !filled))
                .contentShape(Capsule())
                .opacity(busy ? 0.5 : 1)
        }
        .buttonStyle(.soulPressableQuiet)
        .disabled(busy)
    }

    private func chip(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(Theme.body(12, weight: .medium))
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .soulGlassCapsule()
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
        .padding(.vertical, 10)
        .soulGlassCard(tint: Theme.honey.opacity(0.06), stroke: Theme.honey.opacity(0.3))
        .transition(.opacity)
    }
}

/// Glass behind an unfilled pill only — a filled honey pill needs none.
private struct QuietGlassIfNeeded: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.soulGlassCapsule(interactive: true, stroke: Theme.glassBorderHigh)
        } else {
            content
        }
    }
}

/// A face, a name, and whatever control the section puts beside them.
private struct MemberRow<Trailing: View>: View {
    let member: CommunityMember
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(avatarUrl: member.avatarUrl, name: member.displayName,
                       seed: member.id.uuidString, size: 44)
            Text(member.displayName)
                .font(Theme.body(15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(10)
        .padding(.leading, 2)
        .soulGlassCard(radius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(member.displayName)
    }
}

#Preview {
    NavigationStack {
        FriendsView(vm: CommunityViewModel())
    }
    .preferredColorScheme(.dark)
}
