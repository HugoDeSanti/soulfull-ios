//
//  GuideCard.swift
//  Soulfull Gatherings
//
//  The guide, on the page of whatever they made. The way into a guide's
//  profile is always through something of theirs: a digital retreat, a
//  session, a movement sequence, a recipe, a prompt.
//
//  - `GuideCard` — "Your guide": face, name, what they teach. On every
//    practice page and every digital retreat whose content names a guide.
//  - `GuideCredit` — the player's compact "with Alma Guerra" chip, for the
//    sheet where a card would crowd the artwork.
//
//  Both open the profile through `openInstructor`, which the tab's navigation
//  stack puts in the environment. The player is a sheet, and a sheet inherits
//  its presenter's environment — which is how one action serves pushed pages
//  and the player alike. With no stack to push on, the guide still shows; it
//  just doesn't open.
//

import SwiftUI

extension EnvironmentValues {
    /// Opens a guide's profile on the current tab's stack: `(guide id, the
    /// title of the page it came from)` — the second is the profile's back
    /// label. Nil where nothing can push one.
    @Entry var openInstructor: ((_ id: String, _ from: String) -> Void)? = nil
}

struct GuideCard: View {
    private enum Subject: Equatable {
        case instructor(String?)
        case practice(PracticeContentKind, Int)
    }

    private let subject: Subject
    /// The page's title, for the profile's back bar.
    private let from: String
    @Environment(\.openInstructor) private var openInstructor
    private let directory = InstructorDirectory.shared

    /// Content that carries its guide on the row: a digital retreat.
    init(instructorID: String?, from: String) {
        self.subject = .instructor(instructorID)
        self.from = from
    }

    /// A written practice, whose guide is a credit (0020).
    init(kind: PracticeContentKind, contentID: Int, from: String) {
        self.subject = .practice(kind, contentID)
        self.from = from
    }

    private var instructor: Instructor? {
        switch subject {
        case .instructor(let id):
            directory.instructor(id: id)
        case .practice(let kind, let contentID):
            directory.instructor(id: directory.instructorID(kind: kind, contentID: contentID))
        }
    }

    var body: some View {
        // A real container, never `Group`, so `.task` has something to run on
        // while there's no guide yet — the trap `PresenceLine` fell into.
        VStack(alignment: .leading, spacing: 0) {
            if let instructor {
                PressableCard(haptic: openInstructor != nil, action: {
                    openInstructor?(instructor.id, from)
                }) {
                    card(instructor)
                }
                .disabled(openInstructor == nil)
                .transition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your guide, \(instructor.name)\(instructor.title.map { ", \($0)" } ?? "")")
                .accessibilityHint(openInstructor == nil ? "" : "Opens their profile")
                .accessibilityAddTraits(openInstructor == nil ? [] : .isButton)
                .accessibilityIdentifier("guide-card")
            }
        }
        .animation(.easeOut(duration: 0.25), value: instructor)
        .task { await directory.refresh() }
    }

    private func card(_ instructor: Instructor) -> some View {
        HStack(spacing: 14) {
            AvatarView(avatarUrl: instructor.photoUrl, name: instructor.name,
                       seed: instructor.id, size: 50)
                .padding(3)
                .overlay(Circle().strokeBorder(Theme.honey.opacity(0.4), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR GUIDE")
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .foregroundStyle(Theme.inkSoft)
                Text(instructor.name)
                    .font(Theme.headline(19))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .lineLimit(1)
                if let title = instructor.title {
                    Text(title)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if openInstructor != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .soulGlassCard(radius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// "with Alma Guerra" as a face chip — the player's credit. Falls back to
/// whatever the host drew before (`fallback`) when the media has no guide.
struct GuideCredit<Fallback: View>: View {
    let instructorID: String?
    /// Runs before the profile opens: the player dismisses itself, so the
    /// profile is pushed on the stack underneath rather than behind a sheet.
    var beforeOpen: () -> Void = {}
    /// The title of the page, for the profile's back bar.
    let from: String
    @ViewBuilder var fallback: Fallback

    @Environment(\.openInstructor) private var openInstructor
    private let directory = InstructorDirectory.shared

    var body: some View {
        VStack(spacing: 0) {
            if let instructor = directory.instructor(id: instructorID), let openInstructor {
                Button {
                    Haptics.tap()
                    beforeOpen()
                    openInstructor(instructor.id, from)
                } label: {
                    HStack(spacing: 8) {
                        AvatarView(avatarUrl: instructor.photoUrl, name: instructor.name,
                                   seed: instructor.id, size: 24)
                        Text("with \(instructor.name)")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 11)
                    .padding(.vertical, 4)
                    .soulGlassCapsule(interactive: true, stroke: Theme.glassBorderHigh)
                    .contentShape(Capsule())
                }
                .buttonStyle(.soulPressableQuiet)
                .transition(.opacity)
                .accessibilityLabel("with \(instructor.name)")
                .accessibilityHint("Opens their profile")
                .accessibilityIdentifier("guide-credit")
            } else {
                fallback
            }
        }
        .animation(.easeOut(duration: 0.25), value: directory.instructor(id: instructorID))
        .task { await directory.refresh() }
    }
}

#Preview {
    ZStack {
        PhotoBackdrop(imageName: "home-bg", blur: 24, darken: 0.8)
        VStack(alignment: .leading, spacing: 24) {
            GuideCard(instructorID: "alma-guerra", from: "Finding Ground")
            GuideCredit(instructorID: nil, from: "Breath of Fire") {
                Text("with Alma Guerra").font(Theme.body(13)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(20)
    }
    .environment(\.openInstructor) { _, _ in }
    .preferredColorScheme(.dark)
}
