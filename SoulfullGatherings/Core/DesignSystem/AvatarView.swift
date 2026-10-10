//
//  AvatarView.swift
//  Soulfull Gatherings
//
//  A member's face in a circle — their photo when they've set one, their
//  initial on a quiet tone when they haven't. A face is the one surface the
//  app keeps round; everything else is square. The tone is picked from the
//  member's id, so the same person always gets the same colour and a feed of
//  people without photos still reads as a feed of different people.
//

import SwiftUI

struct AvatarView: View {
    /// `avatars/<id>/<uuid>.jpg` in Storage, or nil for the initial.
    let avatarUrl: String?
    /// What the initial is taken from — the display name.
    let name: String
    /// Stable identity, for the tone. The user id.
    var seed: String = ""
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            if let avatarUrl, !avatarUrl.isEmpty {
                CatalogImage(avatarUrl) { $0.resizable().scaledToFill() }
            } else {
                Self.tone(for: seed.isEmpty ? name : seed)
                Text(initial)
                    .font(Theme.headline(size * 0.42, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.glassBorder, lineWidth: Theme.hairline))
        .accessibilityHidden(true)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "·" }
        return String(first).uppercased()
    }

    /// Five tones off the atmospheres: moss, ember, dusk, slate and an umber.
    /// All dark enough for ink, all quiet enough to sit on black.
    private static let tones: [LinearGradient] = [
        (Color(red: 0.27, green: 0.30, blue: 0.11), Color(red: 0.15, green: 0.17, blue: 0.05)),
        (Color(red: 0.45, green: 0.25, blue: 0.12), Color(red: 0.27, green: 0.13, blue: 0.05)),
        (Color(red: 0.42, green: 0.24, blue: 0.22), Color(red: 0.25, green: 0.13, blue: 0.12)),
        (Color(red: 0.20, green: 0.25, blue: 0.33), Color(red: 0.10, green: 0.13, blue: 0.19)),
        (Color(red: 0.33, green: 0.27, blue: 0.20), Color(red: 0.19, green: 0.15, blue: 0.10)),
    ].map { LinearGradient(colors: [$0.0, $0.1], startPoint: .topLeading, endPoint: .bottomTrailing) }

    static func tone(for seed: String) -> LinearGradient {
        // A stable hash — `hashValue` is salted per process and would move a
        // member's colour between launches.
        let sum = seed.utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) }
        return tones[Int(sum % UInt32(tones.count))]
    }
}

#Preview {
    ZStack {
        Atmosphere(tone: .dusk)
        HStack(spacing: 16) {
            AvatarView(avatarUrl: nil, name: "Hugo D.", seed: "a", size: 56)
            AvatarView(avatarUrl: nil, name: "Alma G.", seed: "b", size: 56)
            AvatarView(avatarUrl: nil, name: "Nia", seed: "c", size: 56)
            AvatarView(avatarUrl: nil, name: "", seed: "d", size: 56)
        }
    }
    .preferredColorScheme(.dark)
}
