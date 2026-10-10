//
//  BlockedMembersView.swift
//  Soulfull Gatherings
//
//  "Blocked members", a sheet from the You tab's Community section: who you've
//  blocked, and Unblock beside each.
//

import SwiftUI

struct BlockedMembersView: View {
    @State private var vm = BlockedMembersViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                if let error = vm.actionError {
                    banner(error)
                }
                content
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .refreshable { await vm.load() }
        .background { PhotoBackdrop(imageName: "welcome-bg", blur: 28, darken: 0.86, topScrim: 0) }
        .safeAreaInset(edge: .top, spacing: 0) { closeBar }
        .preferredColorScheme(.dark)
        .presentationCornerRadius(0)
        .task { await vm.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMUNITY")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
            Text("Blocked members")
                .font(Theme.headline(30, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.6)
            Text("You and the people you block don't see each other anywhere in Community. Unblocking doesn't bring back a friendship or likes the block ended.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPhoto()
    }

    @ViewBuilder
    private var content: some View {
        if !vm.hasLoaded && vm.failure == nil {
            ProgressView()
                .tint(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
        } else if let failure = vm.failure, vm.members.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(failure == .offline ? "You're offline" : "Couldn't load this list")
                    .font(Theme.headline(22, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
                Text(failure == .offline
                     ? "Reconnect to see who you've blocked."
                     : "Something went wrong at our end. Please try again in a moment.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .fixedSize(horizontal: false, vertical: true)
                SGPrimaryButton(title: "Try again") { Task { await vm.load() } }
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onPhoto()
            .padding(.top, 22)
            .overlay(alignment: .top) { Hairline() }
        } else if vm.members.isEmpty {
            Text("You haven't blocked anyone. You can block a member from the ⋯ beside their name in Community.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .onPhoto()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 22)
                .overlay(alignment: .top) { Hairline() }
                .accessibilityIdentifier("blocked-empty")
        } else {
            // Open rows on the photo, ruled above and between.
            VStack(spacing: 0) {
                ForEach(vm.members) { member in
                    row(member)
                        .overlay(alignment: .top) { Hairline() }
                        .listReveal()
                }
            }
            .animation(Theme.Motion.settle, value: vm.members)
        }
    }

    private func row(_ member: CommunityMember) -> some View {
        HStack(spacing: 12) {
            AvatarView(avatarUrl: member.avatarUrl, name: member.displayName,
                       seed: member.id.uuidString, size: 44)
            Text(member.displayName)
                .font(Theme.body(15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .onPhoto()
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Haptics.bump()
                Task { await vm.unblock(member) }
            } label: {
                Text("Unblock")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .onPhoto()
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .overlay(Rectangle().strokeBorder(Theme.ink.opacity(0.7), lineWidth: Theme.hairline))
                    // A 44pt target around the 34pt block.
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .opacity(vm.busy.contains(member.id) ? 0.5 : 1)
            }
            .buttonStyle(.soulPressableQuiet)
            .disabled(vm.busy.contains(member.id))
            .accessibilityLabel("Unblock \(member.displayName)")
            .accessibilityIdentifier("unblock")
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blocked-row")
    }

    private func banner(_ message: String) -> some View {
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
        .soulGlassCard(stroke: Theme.ember.opacity(0.35))
    }

    private var closeBar: some View {
        HStack {
            Spacer()
            GlyphButton(systemName: "xmark") {
                Haptics.tap()
                dismiss()
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("blocked-close")
        }
        // The glyph sits about a gutter from the edge; its 44pt target
        // reaches past it.
        .padding(.horizontal, Theme.gutter - 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [Theme.bg.opacity(0.92), Theme.bg.opacity(0.6), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
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
    BlockedMembersView()
}
