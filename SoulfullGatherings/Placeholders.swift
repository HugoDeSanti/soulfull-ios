//
//  Placeholders.swift
//  Soulfull Gatherings
//
//  Practice / Circle / You — themed empty-states for tabs outside the
//  current core-flow scope. Each one keeps the same dark/photo treatment
//  so the app still feels whole.
//

import SwiftUI

struct LibraryPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            eyebrow: "Wellness Library",
            headline: "Practices, returning.",
            message: "Curated sessions for every state — meditation, breathwork, somatic, and more. Coming next."
        )
    }
}

struct CommunityPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            eyebrow: "Community",
            headline: "Your circles, your people.",
            message: "Live circles, member directory, and DMs land here next."
        )
    }
}

struct ProfilePlaceholder: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: "home-bg", blur: 4, darken: 0.7)

            VStack(spacing: 18) {
                Spacer()
                Image("soulfull-logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 88, height: 88)
                    .opacity(0.9)
                Text((settings.userName.isEmpty ? "You" : settings.userName).uppercased())
                    .font(Theme.eyebrow(12))
                    .tracking(3)
                    .foregroundStyle(Theme.ink)
                Text("Welcome back.")
                    .font(Theme.headline(36))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)

                if !settings.intentions.isEmpty {
                    Text("Intentions: " + settings.intentions.sorted().joined(separator: " · "))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                Spacer()

                Button {
                    Haptics.tap()
                    app.resetAll()
                } label: {
                    Text("Reset onboarding")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 120)
            }
        }
    }
}

// MARK: - Shared empty-state body

struct TabPlaceholder: View {
    let eyebrow: String
    let headline: String
    let message: String

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: "home-bg", blur: 4, darken: 0.7)

            VStack(spacing: 18) {
                Spacer()
                Image("soulfull-logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 72, height: 72)
                    .opacity(0.85)
                Text(eyebrow.uppercased())
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.muted)
                Text(headline)
                    .font(Theme.headline(34))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .kerning(-0.3)
                    .frame(maxWidth: 320)
                Text(message)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 320)
                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 100)
        }
    }
}
