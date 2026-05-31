//
//  AccountView.swift
//  Soulfull Gatherings
//
//  Create-account / sign-in sheet. Presented from the You tab; on success it
//  dismisses back to the profile. Styled with the shared glass + Theme chrome.
//

import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings

    @State private var vm: AccountViewModel
    @FocusState private var focus: Field?

    private enum Field { case name, email, password }

    init(mode: AccountViewModel.Mode = .createAccount) {
        _vm = State(initialValue: AccountViewModel(mode: mode))
    }

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: "home-bg", blur: 8, darken: 0.74)

            ScrollView {
                VStack(spacing: 22) {
                    header
                    fields
                    if let msg = vm.errorMessage { errorBanner(msg) }
                    submitButton
                    modeToggle
                }
                .padding(.horizontal, 26)
                .padding(.top, 84)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            closeButton
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image("soulfull-logo-white")
                .resizable().scaledToFit()
                .frame(width: 64, height: 64)
                .opacity(0.9)
            Text(vm.mode.title)
                .font(Theme.headline(30))
                .foregroundStyle(Theme.ink)
                .kerning(-0.3)
                .multilineTextAlignment(.center)
            Text(vm.mode.subtitle)
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 300)
        }
        .padding(.bottom, 6)
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(spacing: 14) {
            if vm.mode == .createAccount {
                inputRow(icon: "person", placeholder: "Your name", text: $vm.fullName, field: .name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
            }
            inputRow(icon: "envelope", placeholder: "Email", text: $vm.email, field: .email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .password }
            inputRow(icon: "lock", placeholder: "Password", text: $vm.password, field: .password, secure: true)
                .submitLabel(.go)
                .onSubmit { Task { await trySubmit() } }
        }
    }

    @ViewBuilder
    private func inputRow(icon: String, placeholder: String, text: Binding<String>,
                          field: Field, secure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 22)
            Group {
                if secure {
                    SecureField("", text: text, prompt: prompt(placeholder))
                } else {
                    TextField("", text: text, prompt: prompt(placeholder))
                }
            }
            .focused($focus, equals: field)
            .font(Theme.body(16))
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(focus == field ? Theme.glassBorderHigh : Theme.glassBorder, lineWidth: 1)
        )
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(Theme.muted)
    }

    // MARK: - Error banner

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(Theme.body(13))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.honey.opacity(0.5), lineWidth: 1)
            )
    }

    // MARK: - Actions

    private var submitButton: some View {
        SGPrimaryButton(
            title: vm.isWorking ? "One moment…" : vm.mode.cta,
            enabled: vm.canSubmit,
            filled: true
        ) {
            Task { await trySubmit() }
        }
        .padding(.top, 4)
    }

    private var modeToggle: some View {
        Button {
            vm.toggleMode()
        } label: {
            HStack(spacing: 6) {
                Text(vm.mode == .createAccount ? "Already have an account?" : "New here?")
                    .foregroundStyle(Theme.muted)
                Text(vm.mode == .createAccount ? "Sign in" : "Create account")
                    .foregroundStyle(Theme.ink)
                    .underline()
            }
            .font(Theme.body(13))
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                CircleIconButton(systemName: "xmark", size: 38) {
                    Haptics.tap()
                    dismiss()
                }
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    private func trySubmit() async {
        focus = nil
        if await vm.submit(auth: auth, settings: settings) { dismiss() }
    }
}

#Preview {
    let app = AppState()
    return AccountView()
        .environment(app.auth)
        .environment(app.settings)
}
