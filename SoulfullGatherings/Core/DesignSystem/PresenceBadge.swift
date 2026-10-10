//
//  PresenceBadge.swift
//  Soulfull Gatherings
//
//  Three overlapping faces and "75.7k present". Quiet on purpose: it sits
//  under a row's metadata and reads as company, not as a leaderboard.
//
//  `PresenceLine` is the one feature code uses — it reads `PresenceStore`
//  and renders nothing at all when there's no count (fewer than 3 people,
//  offline, or not yet loaded), so no row needs an `if`.
//

import SwiftUI

struct PresenceBadge: View {
    let presence: Presence
    var faceSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            if !presence.faces.isEmpty {
                HStack(spacing: -faceSize * 0.3) {
                    ForEach(Array(presence.faces.prefix(3).enumerated()), id: \.element.id) { index, member in
                        AvatarView(avatarUrl: member.avatarUrl, name: member.displayName,
                                   seed: member.id.uuidString, size: faceSize)
                            // Leftmost on top, so the first face — a friend,
                            // when there is one — is the one fully shown.
                            .zIndex(Double(3 - index))
                    }
                }
            }
            Text(presence.label)
                .font(Theme.body(12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("presence-badge")
    }

    private var accessibilityText: String {
        let number = presence.count.formatted()
        let names = presence.faces.prefix(3).map(\.displayName)
        guard !names.isEmpty else { return "\(number) present" }
        return "\(number) present, including \(names.formatted(.list(type: .and)))"
    }
}

/// A practice's or a program's presence, or nothing. Loads on appear.
struct PresenceLine: View {
    private enum Subject: Hashable {
        case practice(PracticeContentKind, Int)
        case program(String)
    }

    private let subject: Subject
    private let faceSize: CGFloat
    private let store = PresenceStore.shared

    init(kind: PracticeContentKind, contentID: Int, faceSize: CGFloat = 20) {
        self.subject = .practice(kind, contentID)
        self.faceSize = faceSize
    }

    init(programID: String, faceSize: CGFloat = 20) {
        self.subject = .program(programID)
        self.faceSize = faceSize
    }

    private var presence: Presence? {
        switch subject {
        case .practice(let kind, let id): store.presence(kind: kind, contentID: id)
        case .program(let id):            store.presence(programID: id)
        }
    }

    var body: some View {
        // A real container, never `Group`: a Group hands its modifiers to its
        // children, so with no presence yet there was nothing to run `.task`
        // on and the first load never happened. An empty VStack still exists.
        VStack(alignment: .leading, spacing: 0) {
            if let presence {
                PresenceBadge(presence: presence, faceSize: faceSize)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.reveal, value: presence)
        .task { await store.refresh() }
    }
}

#Preview {
    ZStack {
        Atmosphere()
        VStack(alignment: .leading, spacing: 16) {
            PresenceBadge(presence: Presence(count: 75_700, faces: [
                CommunityMember(id: UUID(), displayName: "Alma G.", avatarUrl: nil),
                CommunityMember(id: UUID(), displayName: "Theo R.", avatarUrl: nil),
                CommunityMember(id: UUID(), displayName: "Nia K.", avatarUrl: nil),
            ]))
            PresenceBadge(presence: Presence(count: 1_240, faces: []))
        }
    }
    .preferredColorScheme(.dark)
}
