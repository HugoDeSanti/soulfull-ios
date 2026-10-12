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
//  "Forgot password?" on the sign-in form works the same way: a code by email,
//  then a new password.
//

import SwiftUI

struct AccountView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings

    @State private var vm: AccountViewModel
    @FocusState private var focus: Field?
    /// The date-of-birth wheel, open under its row.
    @State private var showDateWheel = false

    private enum Field { case firstName, lastName, email, password, code, newPassword }

    /// - Parameter initialName: seeds the name fields. Onboarding already
    ///   asked for the first name.
    init(mode: AccountViewModel.Mode = .createAccount, initialName: MemberName = MemberName()) {
        let model = AccountViewModel(mode: mode)
        model.firstName = initialName.first
        model.lastName = initialName.last
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
                VStack(spacing: 24) {
                    if vm.awaitingConfirmation {
                        confirmationPanel
                    } else if let step = vm.passwordReset {
                        switch step {
                        case .request: resetRequestPanel
                        case .newPassword: newPasswordPanel
                        }
                    } else {
                        header
                        appleButton
                        emailDivider
                        fields
                        if let msg = vm.errorMessage { errorBanner(msg) }
                        submitButton
                        modeToggle
                        agreement
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 84)
                .padding(.bottom, 40)
                .animation(Theme.Motion.settle, value: vm.passwordReset)
                .animation(Theme.Motion.settle, value: vm.resetCodeAccepted)
            }
            .scrollDismissesKeyboard(.interactively)

            closeButton
        }
        .preferredColorScheme(.dark)
        // Square, like every other surface: the system sheet's rounded top
        // was the one curve left on screen.
        .presentationCornerRadius(Theme.Corner.sheet)
        // Swiping the sheet away mid-request used to strand the result on a
        // view model nobody was showing: a sign-up that needed confirming
        // never reached the panel, or the watch below.
        .interactiveDismissDisabled(vm.isWorking)
        .onAppear {
            // A confirmation started earlier (this sheet was closed, or the app
            // relaunched) goes straight back to its code panel. A fresh create
            // form here invited a second submit, which either hit the send
            // rate limit or invalidated the code they already had.
            if !vm.awaitingConfirmation, let address = auth.confirmationToResume {
                vm.resumeConfirmation(for: address)
            }
        }
        .onChange(of: auth.hasAccount) { _, hasAccount in
            // The account went permanent while this sheet was open: the emailed
            // link was tapped (deep link), or the watch below noticed a
            // confirmation made on another device. Close back to what they
            // were doing.
            //
            // Not while a request of this sheet's own is running. That request
            // dismisses when it's done (see `trySubmit`). Closing here cut in
            // ahead of the profile hydration that follows a sign-in, so the
            // gate replayed the tap before the saved answers had arrived, and
            // Welcome would route on a name that wasn't there yet.
            //
            // Nor when a reset code signed them in: the new password is still
            // to come, and the sheet closes once it's set.
            if hasAccount, !vm.isWorking, !vm.resetCodeAccepted { dismiss() }
        }
        .onChange(of: focus) { _, field in
            // Typing elsewhere puts the wheel away; the date stays.
            if field != nil, showDateWheel {
                withAnimation(Theme.Motion.settle) { showDateWheel = false }
            }
        }
        .onChange(of: vm.passwordReset) { _, step in
            switch step {
            case .request?: focus = vm.email.isEmpty ? .email : nil
            case .newPassword?: focus = .code
            case nil: focus = nil
            }
        }
        .onChange(of: vm.resetCodeAccepted) { _, accepted in
            if accepted { focus = .newPassword }
        }
        .onChange(of: vm.awaitingConfirmation) { _, awaiting in
            if awaiting {
                // Owned by AuthManager, not by this sheet — so confirming on a
                // laptop still lands here after the user swipes the sheet away.
                auth.beginConfirmationWatch()
                focus = .code
            } else {
                auth.endConfirmationWatch()
            }
        }
        // Only the resend cooldown is this sheet's to cancel. Cancelling the
        // confirmation watch here is what made the watch useless.
        .onDisappear { vm.endCooldown() }
    }

    // MARK: - Email confirmation panel

    private var confirmationPanel: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(Theme.ink)
            panelHeading("Almost there — confirm your email",
                         "We sent a code to \(vm.confirmationEmail). Enter it below — it works wherever you read the email, phone or laptop.")

            codeField(text: $vm.confirmationCode, label: "Confirmation code", identifier: "confirmation-code")

            if let msg = vm.errorMessage { errorBanner(msg) }
            if let msg = vm.resendMessage { resendNote(msg) }

            SGPrimaryButton(
                title: vm.isWorking ? "One moment…" : "Confirm email",
                enabled: vm.canConfirm,
                filled: true
            ) {
                Task { await tryConfirm() }
            }

            resendButton { await vm.resendCode(auth: auth) }

            // A confirmation that never arrives shouldn't strand the user on
            // this panel with no way back to the other sign-in options.
            Button {
                Haptics.tap()
                auth.setAsidePendingConfirmation()
                vm.leaveConfirmation()
            } label: {
                Text("Use a different sign-in")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.ink)
                    .underline()
                    .onPhoto()
                    .padding(.vertical, 10)
                    .widerHitArea(vertical: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 24)
    }

    /// One wide field rather than a row of boxes: `.oneTimeCode` lets iOS offer
    /// the code straight from Mail, a single field is what autofill targets, and
    /// it doesn't bake in a digit count the project can change.
    private func codeField(text: Binding<String>, label: String, identifier: String) -> some View {
        TextField("", text: text, prompt: Text("Code").foregroundStyle(Theme.muted))
            .focused($focus, equals: .code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .font(Theme.headline(28, weight: .light))
            .kerning(10)
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .soulGlass(in: Theme.controlShape,
                       stroke: focus == .code ? Theme.ink.opacity(0.6) : Theme.glassBorder)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
    }

    private func resendNote(_ msg: String) -> some View {
        Text(msg)
            .font(Theme.body(12))
            .foregroundStyle(Theme.inkOnPhoto)
            .onPhoto()
    }

    private func resendButton(_ send: @escaping () async -> Void) -> some View {
        Button {
            Haptics.tap()
            Task { await send() }
        } label: {
            Text(vm.resendCooldown > 0 ? "Send a new code in \(vm.resendCooldown)s" : "Send a new code")
                .font(Theme.body(13))
                .foregroundStyle(vm.resendCooldown > 0 ? Theme.inkSoft : Theme.ink)
                .underline(vm.resendCooldown == 0)
                .onPhoto()
                .padding(.vertical, 6)
                .widerHitArea(vertical: 8)
        }
        .buttonStyle(.plain)
        .disabled(vm.resendCooldown > 0 || vm.isWorking)
    }

    // MARK: - Forgot password

    private var resetRequestPanel: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            panelHeading("Forgot your password?",
                         "Enter the email you use with Soulfull and we'll send you a code to choose a new one.")

            inputRow(icon: "envelope", placeholder: "Email", text: $vm.email, field: .email,
                     contentType: .username, identifier: "reset-email")
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { Task { await vm.sendResetCode(resetBackend) } }

            if let msg = vm.errorMessage { errorBanner(msg) }

            SGPrimaryButton(
                title: vm.isWorking ? "One moment…" : "Send code",
                enabled: vm.canSendResetCode,
                filled: true
            ) {
                Task { await vm.sendResetCode(resetBackend) }
            }
            .accessibilityIdentifier("reset-send")

            // An Apple sign-in has no password, and a Hide My Email address
            // isn't one anybody would think to type here.
            Text("Joined with Apple? There's no password to reset. Go back and continue with Apple.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.inkOnPhoto)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 280)
                .onPhoto()

            backToSignInButton
        }
        .padding(.top, 24)
    }

    /// The code and the new password together, so it's one step, not two.
    /// Once the code is accepted they're signed in, and if the password is
    /// refused only that field is left.
    private var newPasswordPanel: some View {
        VStack(spacing: 16) {
            Image(systemName: vm.resetCodeAccepted ? "checkmark.seal" : "envelope.badge")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(Theme.ink)
                .contentTransition(.opacity)
                .accessibilityHidden(true)
            if vm.resetCodeAccepted {
                panelHeading("You're signed in",
                             "Now choose the password you'll use from here on.")
            } else {
                // Worded so it doesn't say whether the address has an account.
                panelHeading("Check your email",
                             "If there's an account for \(vm.email), we've sent it a code. Enter it with a new password. The code works wherever you read the email.")
            }

            if !vm.resetCodeAccepted {
                codeField(text: $vm.resetCode, label: "Code from the email", identifier: "reset-code")
            }

            inputRow(icon: "lock", placeholder: "New password", text: $vm.newPassword, field: .newPassword,
                     contentType: .newPassword, hint: "At least 8 characters", secure: true,
                     identifier: "reset-new-password")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { Task { await trySetNewPassword() } }
            passwordRule

            if let msg = vm.errorMessage { errorBanner(msg) }
            if let msg = vm.resendMessage { resendNote(msg) }

            SGPrimaryButton(
                title: vm.isWorking ? "One moment…" : "Set new password",
                enabled: vm.canSetNewPassword,
                filled: true
            ) {
                Task { await trySetNewPassword() }
            }
            .accessibilityIdentifier("reset-submit")

            if !vm.resetCodeAccepted {
                resendButton { await vm.resendResetCode(resetBackend) }
                backToSignInButton
            }
        }
        .padding(.top, 24)
    }

    private func panelHeading(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(Theme.headline(26, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.4)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 300)
        }
        .onPhoto()
    }

    private var backToSignInButton: some View {
        Button {
            Haptics.tap()
            vm.leavePasswordReset()
        } label: {
            Text("Back to sign in")
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink)
                .underline()
                .onPhoto()
                .padding(.vertical, 10)
                .widerHitArea(vertical: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reset-back")
    }

    private var resetBackend: AccountViewModel.PasswordResetBackend {
        vm.resetBackend(auth: auth, settings: settings)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image("soulfull-logo-white")
                .resizable().scaledToFit()
                .frame(width: 64, height: 64)
                .opacity(0.9)
                // Decorative: the title under it says where they are.
                .accessibilityHidden(true)
            Text(vm.mode.title)
                .font(Theme.headline(32, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.6)
                .multilineTextAlignment(.center)
            Text(vm.mode.subtitle)
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 300)
        }
        .onPhoto()
        .padding(.bottom, 12)
    }

    // MARK: - Sign in with Apple

    private var appleButton: some View {
        AppleSignInButton(
            disabled: vm.isWorking,
            onCredential: { credential in
                Task {
                    let outcome = await vm.submitApple(credential, auth: auth, settings: settings)
                    if outcome == .signedIn || auth.hasAccount { dismiss() }
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
                .foregroundStyle(Theme.inkSoft)
                .onPhoto()
            line
        }
        .padding(.vertical, 2)
    }

    private var line: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Fields

    private var fields: some View {
        let creating = vm.mode == .createAccount
        return VStack(spacing: 14) {
            if creating {
                // Two rows, the second with no glyph of its own: one name,
                // the profile's two parts (0033).
                inputRow(icon: "person", placeholder: "First name", text: $vm.firstName, field: .firstName,
                         contentType: .givenName, identifier: "account-first-name")
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focus = .lastName }
                inputRow(icon: nil, placeholder: "Last name", text: $vm.lastName, field: .lastName,
                         contentType: .familyName, identifier: "account-last-name")
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit {
                        focus = nil
                        showDateWheel = true
                    }
                dateOfBirthRow
                if showDateWheel { dateOfBirthWheel }
                fieldHint("Private, never shown to other members. You need to be 13 or older.")
            }
            // `.username` on the address, not `.emailAddress`: it's what Password
            // AutoFill pairs a saved (or newly suggested) password with.
            inputRow(icon: "envelope", placeholder: "Email", text: $vm.email, field: .email,
                     contentType: .username, identifier: "account-email")
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .password }
            // `.newPassword` offers a strong password on create (20 characters,
            // well past the rule); `.password` fills a saved one on sign-in.
            inputRow(icon: "lock", placeholder: "Password", text: $vm.password, field: .password,
                     contentType: creating ? .newPassword : .password,
                     hint: creating ? "At least 8 characters" : "", secure: true,
                     identifier: "account-password")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { Task { await trySubmit() } }
            if creating {
                passwordRule
            } else {
                forgotPasswordButton
            }
        }
    }

    /// The rule `canSubmit` enforces. Without it the button simply stayed dim
    /// at seven characters, with nothing saying why.
    private var passwordRule: some View {
        fieldHint("At least 8 characters")
            // Spoken as the password field's hint instead.
            .accessibilityHidden(true)
    }

    private func fieldHint(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(12))
            .foregroundStyle(Theme.inkOnPhoto)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 18)
            .padding(.top, -6)
            .onPhoto()
    }

    /// A row like the fields around it, opening a wheel rather than a
    /// keyboard. Turning the wheel is what answers (`dateOfBirthWheel`).
    private var dateOfBirthRow: some View {
        Button {
            focus = nil
            withAnimation(Theme.Motion.settle) { showDateWheel.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(vm.dateOfBirth.map { BirthDate($0).formatted } ?? "Date of birth")
                    .font(Theme.body(16))
                    .foregroundStyle(vm.dateOfBirth == nil ? Theme.muted : Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .soulGlass(in: Theme.controlShape,
                       stroke: showDateWheel ? Theme.ink.opacity(0.6) : Theme.glassBorder)
        }
        .buttonStyle(.soulPressable)
        .accessibilityLabel("Date of birth")
        .accessibilityValue(vm.dateOfBirth.map { BirthDate($0).formatted } ?? "Not set")
        .accessibilityHint("Private, never shown to other members. You need to be 13 or older.")
        .accessibilityIdentifier("account-dob")
    }

    /// Bounded at 13 years ago, so a younger date can't be picked rather than
    /// being refused after the fact.
    private var dateOfBirthWheel: some View {
        DatePicker("Date of birth",
                   selection: $vm.dateOfBirthWheel,
                   in: BirthDate.earliest()...BirthDate.latest(now: AppClock.shared.now),
                   displayedComponents: .date)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .tint(Theme.ink)
            .frame(maxWidth: .infinity)
            .soulGlass(in: Theme.cardShape)
            .transition(.opacity)
            .accessibilityIdentifier("account-dob-wheel")
    }

    private var forgotPasswordButton: some View {
        Button {
            Haptics.tap()
            vm.beginPasswordReset()
        } label: {
            Text("Forgot password?")
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink)
                .underline()
                .onPhoto()
                .widerHitArea(vertical: 14)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 8)
        .padding(.top, -2)
        .accessibilityIdentifier("forgot-password")
    }

    @ViewBuilder
    private func inputRow(icon: String?, placeholder: String, text: Binding<String>,
                          field: Field, contentType: UITextContentType,
                          hint: String = "", secure: Bool = false,
                          identifier: String = "") -> some View {
        HStack(spacing: 12) {
            // Without a glyph the slot stays, so every field's text starts
            // on the same line.
            Image(systemName: icon ?? "person")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Theme.muted)
                .frame(width: 22)
                .opacity(icon == nil ? 0 : 1)
                .accessibilityHidden(true)
            Group {
                if secure {
                    SecureField("", text: text, prompt: prompt(placeholder))
                } else {
                    TextField("", text: text, prompt: prompt(placeholder))
                }
            }
            .focused($focus, equals: field)
            .textContentType(contentType)
            .font(Theme.body(16))
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            // The empty title left VoiceOver with nothing to call the field
            // once it had text in it; the prompt is only read while empty.
            .accessibilityLabel(placeholder)
            .accessibilityHint(hint)
            .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .soulGlass(in: Theme.controlShape,
                   stroke: focus == field ? Theme.ink.opacity(0.6) : Theme.glassBorder)
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
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .soulGlass(in: Theme.controlShape, stroke: Theme.ember.opacity(0.5))
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
                    .foregroundStyle(Theme.inkSoft)
                Text(vm.mode == .createAccount ? "Sign in" : "Create account")
                    .foregroundStyle(Theme.ink)
                    .underline()
            }
            .font(Theme.body(13))
            .onPhoto()
            .widerHitArea(vertical: 14)
        }
        .buttonStyle(.plain)
    }

    /// What continuing agrees to, and what other members will see — said here
    /// because this is where an account (Apple or email) comes into being.
    /// The Terms carry the community standards Guideline 1.2 asks members to
    /// agree to; the visibility line is the disclosure `share_activity`
    /// (on by default) needs.
    private var agreement: some View {
        Text(Self.agreementText)
            .font(Theme.body(12))
            // On the photo: `muted` sank into it. The links stand out in ink.
            .foregroundStyle(Theme.inkSoft)
            .tint(Theme.ink)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .onPhoto()
            .padding(.horizontal, 6)
            .accessibilityIdentifier("account-agreement")
    }

    private static let agreementText: AttributedString = {
        let markdown = "Other members see your first name, last initial and photo in Community. By continuing, you agree to our [Terms](\(LegalLinks.terms.absoluteString)), including our community standards, and acknowledge our [Privacy Policy](\(LegalLinks.privacyPolicy.absoluteString))."
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }()

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                GlyphButton(systemName: "xmark") {
                    Haptics.tap()
                    dismiss()
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("account-close")
            }
            Spacer()
        }
        // The glyph's 44pt square centres it on the gutter.
        .padding(.horizontal, Theme.gutter - 13)
        .padding(.top, 10)
    }

    /// Dismisses on success, and also when the account went permanent by
    /// another route (the emailed link, the watch) while this request was
    /// running, which `onChange(of: auth.hasAccount)` stands aside for.
    /// Otherwise the VM drives the confirmation panel and the error banner.
    private func trySubmit() async {
        focus = nil
        let outcome = await vm.submit(auth: auth, settings: settings)
        if outcome == .signedIn || auth.hasAccount { dismiss() }
    }

    private func tryConfirm() async {
        focus = nil
        let outcome = await vm.confirmCode(auth: auth, settings: settings)
        if outcome == .signedIn || auth.hasAccount { dismiss() }
    }

    /// Not `|| auth.hasAccount` as above: an accepted code signs them in
    /// before the password is set, and a refused password keeps the sheet up.
    private func trySetNewPassword() async {
        focus = nil
        let outcome = await vm.setNewPassword(resetBackend)
        if outcome == .signedIn { dismiss() }
    }
}

private extension View {
    /// Grows a line-of-text button's hit area to about 44pt tall without
    /// moving anything: the padding widens the tappable shape, and the
    /// negative padding hands the room back to the layout. Plain-style buttons
    /// answer only where they draw, so these were 16–36pt targets
    /// (gotcha #5). `vertical` is what each side needs to reach 44.
    func widerHitArea(vertical: CGFloat, horizontal: CGFloat = 10) -> some View {
        padding(.vertical, vertical)
            .padding(.horizontal, horizontal)
            .contentShape(Rectangle())
            .padding(.vertical, -vertical)
            .padding(.horizontal, -horizontal)
    }
}

#Preview {
    let app = AppState()
    return AccountView()
        .environment(app.auth)
        .environment(app.settings)
}
