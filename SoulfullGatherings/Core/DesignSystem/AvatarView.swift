//
//  AvatarView.swift
//  Soulfull Gatherings
//
//  A member's face in a circle — their photo when they've set one, their
//  initial on a quiet tone when they haven't. The tone is picked from the
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
        .overlay(Circle().strokeBorder(Theme.glassBorderHigh, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "·" }
        return String(first).uppercased()
    }

    /// Five tones off the brand: olive, honey, a dusty rose, a slate, a sand.
    /// All dark enough for cream type, all quiet enough to sit on glass.
    private static let tones: [LinearGradient] = [
        (Color(red: 0.31, green: 0.36, blue: 0.16), Color(red: 0.20, green: 0.24, blue: 0.09)),
        (Color(red: 0.55, green: 0.44, blue: 0.18), Color(red: 0.38, green: 0.29, blue: 0.10)),
        (Color(red: 0.52, green: 0.31, blue: 0.30), Color(red: 0.34, green: 0.19, blue: 0.19)),
        (Color(red: 0.29, green: 0.36, blue: 0.43), Color(red: 0.17, green: 0.23, blue: 0.29)),
        (Color(red: 0.50, green: 0.42, blue: 0.31), Color(red: 0.33, green: 0.27, blue: 0.19)),
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
        PhotoBackdrop(imageName: "home-bg", blur: 4, darken: 0.7)
        HStack(spacing: 16) {
            AvatarView(avatarUrl: nil, name: "Hugo D.", seed: "a", size: 56)
            AvatarView(avatarUrl: nil, name: "Alma G.", seed: "b", size: 56)
            AvatarView(avatarUrl: nil, name: "Nia", seed: "c", size: 56)
            AvatarView(avatarUrl: nil, name: "", seed: "d", size: 56)
        }
    }
    .preferredColorScheme(.dark)
}
