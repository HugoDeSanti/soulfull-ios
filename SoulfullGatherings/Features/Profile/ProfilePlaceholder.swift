import SwiftUI

struct ProfilePlaceholder: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var auth

    @State private var showAccount = false
    @State private var accountMode: AccountViewModel.Mode = .createAccount
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

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

                accountStatus

                Spacer()

                accountActions
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

    // MARK: - Account status line

    @ViewBuilder
    private var accountStatus: some View {
        if auth.hasAccount, let email = auth.email {
            Label(email, systemImage: "checkmark.seal.fill")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
        } else {
            Text("Guest · not signed in")
                .font(Theme.body(13))
                .foregroundStyle(Theme.muted)
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
