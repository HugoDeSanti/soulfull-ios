//
//  GuidesShelf.swift
//  Soulfull Gatherings
//
//  The two ways into a guide's profile from the rest of the app:
//
//  - `GuidesShelf` — a row of faces on the Practice landing, one per
//    published guide. Absent until the team has written an `instructors` row.
//  - `GuideCredit` — a digital retreat's "with Alma Guerra", which becomes a
//    face and a way to their profile once the retreat is linked to its guide,
//    and stays the plain line it always was until then.
//

import SwiftUI

struct GuidesShelf: View {
    let instructors: [Instructor]
    let onOpen: (Instructor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THE GUIDES")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
                .onPhoto()

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(instructors) { instructor in
                        card(instructor)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            // Edge to edge, while the first face still lines up with the
            // header above it.
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .padding(.horizontal, -20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The guides")
    }

    private func card(_ instructor: Instructor) -> some View {
        Button {
            onOpen(instructor)
        } label: {
            VStack(spacing: 8) {
                AvatarView(avatarUrl: instructor.photoUrl, name: instructor.name,
                           seed: instructor.id, size: 62)
                    .padding(3)
                    .overlay(Circle().strokeBorder(Theme.honey.opacity(0.4), lineWidth: 1))
                Text(instructor.name)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .onPhoto()
            }
            .frame(width: 80)
            .contentShape(Rectangle())
        }
        .buttonStyle(.soulPressableChip)
        .accessibilityIdentifier("guide-card")
        .accessibilityLabel(instructor.title.map { "\(instructor.name), \($0)" } ?? instructor.name)
        .accessibilityHint("Opens their profile")
    }
}

/// "with Alma Guerra". A face and a way to the guide's profile when the
/// content is linked to a published guide and the screen can open one; the
/// plain line otherwise, exactly as before.
struct GuideCredit: View {
    let lead: String
    let instructorID: String?
    var onOpen: ((String) -> Void)?

    private let directory = InstructorDirectory.shared

    var body: some View {
        // A real container, never `Group`, so `.task` has something to run on
        // while there's no guide yet — the same trap `PresenceLine` fell into.
        VStack(alignment: .leading, spacing: 0) {
            if let instructor = directory.instructor(id: instructorID), let onOpen {
                Button {
                    Haptics.tap()
                    onOpen(instructor.id)
                } label: {
                    HStack(spacing: 8) {
                        AvatarView(avatarUrl: instructor.photoUrl, name: instructor.name,
                                   seed: instructor.id, size: 26)
                        Text("with \(instructor.name)")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 12)
                    .padding(.vertical, 4)
                    .soulGlassCapsule(interactive: true, stroke: Theme.glassBorderHigh)
                    .contentShape(Capsule())
                }
                .buttonStyle(.soulPressableQuiet)
                .transition(.opacity)
                .accessibilityIdentifier("program-guide")
                .accessibilityLabel("with \(instructor.name)")
                .accessibilityHint("Opens their profile")
            } else {
                Text("with \(lead)")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .onPhoto()
            }
        }
        .animation(.easeOut(duration: 0.25), value: directory.instructor(id: instructorID))
        .task { await directory.refresh() }
    }
}

#Preview {
    ZStack {
        PhotoBackdrop(imageName: "home-bg", blur: 3, darken: 0.76)
        VStack(alignment: .leading, spacing: 24) {
            GuidesShelf(instructors: [
                Instructor(id: "a", name: "Alma Guerra", title: nil, bio: nil, photoUrl: nil),
                Instructor(id: "b", name: "Mara Solé", title: nil, bio: nil, photoUrl: nil),
                Instructor(id: "c", name: "Rodrigo Peán", title: nil, bio: nil, photoUrl: nil),
            ], onOpen: { _ in })
            GuideCredit(lead: "Alma Guerra", instructorID: nil)
        }
        .padding(20)
    }
    .preferredColorScheme(.dark)
}
