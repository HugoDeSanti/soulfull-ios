//
//  AccountView.swift
//  Soulfull Gatherings
//
//  Create-account / sign-in sheet. Presented from the You tab, and raised by
//  `AccountGate` the first time a guest reaches for a practice — on success it
//  dismisses and the gate replays the tap they were making.
//  Sign in with Apple comes first; email/password sits underneath as the fallback.
//  When email confirmation is pending, the sheet swaps to a code panel: the
//  emailed link only completes on this device, so the emailed code is the path
//  that works from a laptop, a work machine, anywhere.
//

import SwiftUI

struct AccountView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings

    @State private var vm: AccountViewModel
    @FocusState private var focus: Field?

    private enum Field { case name, email, password, code }

    /// - Parameter initialName: seeds the name field — onboarding already asked.
    init(mode: AccountViewModel.Mode = .createAccount, initialName: String = "") {
        let model = AccountViewModel(mode: mode)
        model.fullName = initialName
        _vm = State(initialValue: model)
    }

    #if DEBUG
    /// Opens straight on the confirm-your-email panel (`-preview-confirm-email`),
    /// which otherwise needs a real sign-up against a project with confirmation
    /// on. No watch starts — `awaitingConfirmation` never *changes* — so this
    /// stays a purely visual pass.
    init(previewConfirmationFor email: String) {
        let model = AccountViewModel(mode: .createAccount)
        model.email = email
        model.awaitingConfirmation = true
        _vm = State(initialValue: model)
    }
    #endif

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: "home-bg", blur: 8, darken: 0.74)

            ScrollView {
                VStack(spacing: 22) {
                    if vm.awaitingConfirmation {
                        confirmationPanel
                    } else {
                        header
                        appleButton
                        emailDivider
                        fields
                        if let msg = vm.errorMessage { errorBanner(msg) }
                        submitButton
                        modeToggle
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 84)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            closeButton
        }
        .preferredColorScheme(.dark)
        .onChange(of: auth.hasAccount) { _, hasAccount in
            // The account went permanent while this sheet was open — the emailed
            // link was tapped (deep link), the code was accepted, or the watch
            // below noticed a confirmation made on another device. Either way,
            // close back to what they were doing.
            if hasAccount { dismiss() }
        }
        .onChange(of: vm.awaitingConfirmation) { _, awaiting in
            if awaiting {
                vm.beginConfirmationWatch(auth: auth, settings: settings)
                focus = .code
            } else {
                vm.endConfirmationWatch()
            }
        }
        .onDisappear { vm.endConfirmationWatch() }
    }

    // MARK: - Email confirmation panel

    private var confirmationPanel: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.honey)
            VStack(spacing: 16) {
                Text("Almost there — confirm your email")
                    .font(Theme.headline(24))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                    .multilineTextAlignment(.center)
                Text("We sent a code to \(vm.confirmationEmail). Enter it below — it works wherever you read the email, phone or laptop.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 300)
            }
            // Copy only: the halo must not wrap the code field below it.
            .onPhoto()

            codeField

            if let msg = vm.errorMessage { errorBanner(msg) }
            if let msg = vm.resendMessage {
                Text(msg)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
            }

            SGPrimaryButton(
                title: vm.isWorking ? "One moment…" : "Confirm email",
                enabled: vm.canConfirm,
                filled: true
            ) {
                Task { await tryConfirm() }
            }

            resendButton

            // A confirmation that never arrives shouldn't strand the user on
            // this panel with no way back to the other sign-in options.
            Button {
                Haptics.tap()
                vm.awaitingConfirmation = false
            } label: {
                Text("Use a different sign-in")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.ink)
                    .underline()
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 24)
    }

    /// One wide field rather than a row of boxes: `.oneTimeCode` lets iOS offer
    /// the code straight from Mail, a single field is what autofill targets, and
    /// it doesn't bake in a digit count the project can change.
    private var codeField: some View {
        TextField("", text: $vm.confirmationCode, prompt: Text("Code").foregroundStyle(Theme.muted))
            .focused($focus, equals: .code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .font(Theme.headline(28))
            .kerning(10)
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(focus == .code ? Theme.glassBorderHigh : Theme.glassBorder, lineWidth: 1)
            )
            .accessibilityLabel("Confirmation code")
            .accessibilityIdentifier("confirmation-code")
    }

    private var resendButton: some View {
        Button {
            Haptics.tap()
            Task { await vm.resendCode(auth: auth) }
        } label: {
            Text(vm.resendCooldown > 0 ? "Send a new code in \(vm.resendCooldown)s" : "Send a new code")
                .font(Theme.body(13))
                .foregroundStyle(vm.resendCooldown > 0 ? Theme.muted : Theme.ink)
                .underline(vm.resendCooldown == 0)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(vm.resendCooldown > 0 || vm.isWorking)
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
                .foregroundStyle(Theme.inkOnPhoto)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 300)
        }
        .padding(.bottom, 6)
        .onPhoto()
    }

    // MARK: - Sign in with Apple

    private var appleButton: some View {
        AppleSignInButton(
            disabled: vm.isWorking,
            onCredential: { token, nonce, name in
                Task {
                    if case .signedIn = await vm.submitApple(idToken: token, nonce: nonce, fullName: name,
                                                             auth: auth, settings: settings) { dismiss() }
                }
            },
            onFailure: { vm.reportAppleFailure($0) }
        )
    }

    private var emailDivider: some View {
        HStack(spacing: 12) {
            line
            Text("or")
                .font(Theme.eyebrow(11))
                .tracking(2)
                .foregroundStyle(Theme.muted)
            line
        }
        .padding(.vertical, 2)
    }

    private var line: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
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
                .accessibilityLabel("Close")
                .accessibilityIdentifier("account-close")
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    private func trySubmit() async {
        focus = nil
        switch await vm.submit(auth: auth, settings: settings) {
        case .signedIn:
            dismiss()
        case .confirmationRequired, .cancelled, .failed:
            break // VM drives the confirmation panel / error banner
        }
    }

    private func tryConfirm() async {
        focus = nil
        if case .signedIn = await vm.confirmCode(auth: auth, settings: settings) { dismiss() }
    }
}

#Preview {
    let app = AppState()
    return AccountView()
        .environment(app.auth)
        .environment(app.settings)
}
