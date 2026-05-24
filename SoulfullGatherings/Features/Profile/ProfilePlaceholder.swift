import SwiftUI

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
