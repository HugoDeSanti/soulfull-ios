import SwiftUI

struct ProfilePlaceholder: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var auth
    @Environment(\.openURL) private var openURL

    @State private var showAccount = false
    @State private var accountMode: AccountViewModel.Mode = .createAccount
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: "home-bg", blur: 4, darken: 0.7)

            AuroraBackground(speed: 0.7)
                .opacity(0.35)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()
                Image("soulfull-logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 88, height: 88)
                    .breathing(scale: 0.96...1.04, opacity: 0.82...0.95, period: 5.5)
                VStack(spacing: 18) {
                    Text((settings.userName.isEmpty ? "You" : settings.userName).uppercased())
                        .font(Theme.eyebrow(12))
                        .tracking(3)
                        .foregroundStyle(Theme.ink)
                    Text("Welcome back.")
                        .font(Theme.headline(36))
                        .foregroundStyle(Theme.ink)
                        .kerning(-0.3)

                    accountStatus
                }
                // This block is centred over the open sky of home-bg, the
                // brightest ground in the app — see View.onPhoto().
                .onPhoto()
                intentionsRow

                Spacer()

                VStack(spacing: 16) {
                    accountActions
                    legalLinks
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 120)
            }
        }
        .sheet(isPresented: $showAccount) {
            AccountView(mode: accountMode)
        }
        .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, reservations, and saved data. This can't be undone.")
        }
        .alert("Couldn't delete account", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await auth.deleteAccount()
            Haptics.success()
        } catch {
            Haptics.bump()
            deleteError = error.localizedDescription
        }
    }

    /// What they came here for, as quiet glass chips.
    @ViewBuilder
    private var intentionsRow: some View {
        let intentions = IntentionOption.all.filter { settings.intentions.contains($0.id) }
        if !intentions.isEmpty {
            HStack(spacing: 8) {
                ForEach(intentions.prefix(3)) { intention in
                    Text(intention.label)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .soulGlassCapsule()
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Account status line

    @ViewBuilder
    private var accountStatus: some View {
        if auth.hasAccount, let email = auth.email {
            Label(email, systemImage: "checkmark.seal.fill")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkOnPhoto)
        } else {
            Text("Guest · not signed in")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: - Actions (sign in/up vs sign out) + dev tools

    @ViewBuilder
    private var accountActions: some View {
        VStack(spacing: 12) {
            if auth.hasAccount {
                SGPrimaryButton(title: "Sign out") {
                    Task { await auth.signOut() }
                }
                Button {
                    Haptics.tap()
                    showDeleteConfirm = true
                } label: {
                    Text(isDeleting ? "Deleting…" : "Delete account")
                        .font(Theme.body(13))
                        .foregroundStyle(Color(red: 0.85, green: 0.36, blue: 0.33))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
            } else {
                SGPrimaryButton(title: "Create account", filled: true) {
                    accountMode = .createAccount
                    showAccount = true
                }
                SGPrimaryButton(title: "Sign in") {
                    accountMode = .signIn
                    showAccount = true
                }
            }
            devReset
        }
    }

    // MARK: - Legal & support

    /// Privacy policy, terms, and a way to reach a human. App Store Connect
    /// requires a resolving privacy policy URL and a support URL, and an app
    /// that creates accounts needs both reachable from inside the app — the
    /// checkout fineprint referring to "the enrollment terms" isn't enough on
    /// its own. Destinations live in `LegalLinks`.
    private var legalLinks: some View {
        HStack(spacing: 0) {
            legalLink("Privacy", url: LegalLinks.privacyPolicy)
            legalDivider
            legalLink("Terms", url: LegalLinks.terms)
            legalDivider
            legalLink("Support", url: LegalLinks.supportMail)
        }
        .padding(.top, 2)
    }

    private var legalDivider: some View {
        Text("·")
            .font(Theme.body(12))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
    }

    private func legalLink(_ title: String, url: URL) -> some View {
        Button {
            Haptics.tap()
            openURL(url)
        } label: {
            Text(title)
                .font(Theme.body(12))
                .foregroundStyle(Theme.inkSoft)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }

    /// Dev-only onboarding reset. Compiled out of Release builds.
    @ViewBuilder
    private var devReset: some View {
        #if DEBUG
        Button {
            Haptics.tap()
            app.resetAll()
        } label: {
            Text("Reset onboarding")
                .font(Theme.body(13))
                .foregroundStyle(Theme.muted)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        #endif
    }
}
