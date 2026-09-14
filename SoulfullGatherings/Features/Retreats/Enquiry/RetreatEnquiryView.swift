//
//  RetreatEnquiryView.swift
//  Soulfull Gatherings
//
//  The retreat application, asked in the app instead of in an empty email.
//
//  "Request a place" used to open a blank `mailto:` with a subject line, which
//  put the whole burden of knowing what to say on the guest and landed the
//  team an inbox of applications that each answered a different set of
//  questions. This asks the same questions the website's "Join a retreat" form
//  asks — same wording, same order, same options (`RetreatEnquiry.Question`) —
//  and hands the finished answers to the system mail composer, addressed to
//  the monitored inbox.
//
//  No account is required. Applying is the start of a conversation with the
//  retreat team, not a member action, and putting a sign-up wall in front of
//  it would be both worse for the guest and a Guideline 5.1.1(i) argument we
//  have already decided not to have (see the account-gate note in CLAUDE.md).
//
//  Type sits on the retreat's own photograph here, so the header follows the
//  one rule: `topScrim` on the backdrop, `.onPhoto()` on the copy — and on the
//  copy only. The fields are UIKit-backed; a shadow over one of those is
//  rendering gotcha #1.
//

import SwiftUI

struct RetreatEnquiryView: View {

    @Environment(\.dismiss) private var dismiss

    let retreat: Retreat

    @State private var vm: RetreatEnquiryViewModel
    @State private var composed: RetreatEnquiry?
    @State private var showComposer = false
    @State private var showNoMailNotice = false
    @State private var showSendFailure = false
    @State private var confirmDiscard = false
    @State private var showDateWheel = false
    @FocusState private var focus: Field?

    private enum Field: String {
        case firstName, lastName, basedIn, phone, instagram, about, email, referral

        /// Accessibility identifier. Stable names so `RetreatEnquiryTests` can
        /// fill the form without matching on placeholder copy.
        var id: String { "enquiry-\(rawValue)" }
    }

    /// - Parameters:
    ///   - initialName: onboarding already asked for a name; it is one word, so
    ///     it seeds the first-name field only.
    ///   - initialEmail: the account's address, when there is an account.
    init(retreat: Retreat, initialName: String = "", initialEmail: String = "") {
        self.retreat = retreat
        _vm = State(initialValue: RetreatEnquiryViewModel(
            retreat: retreat, name: initialName, email: initialEmail
        ))
    }

    var body: some View {
        ZStack {
            PhotoBackdrop(imageName: retreat.imageUrl, blur: 26, darken: 0.86, topScrim: 0.55)

            if vm.didSend {
                sentPanel
            } else {
                form
            }

            closeButton
        }
        .preferredColorScheme(.dark)
        .task { await vm.loadOptions() }
        // The composer is UIKit and must not be wrapped in anything — its own
        // sheet, no effects, edge to edge.
        .sheet(isPresented: $showComposer) {
            if let composed {
                MailComposeView(
                    recipients: [RetreatEnquiry.recipient],
                    subject: composed.mailSubject,
                    body: composed.mailBody,
                    onFinish: handle(_:)
                )
                .ignoresSafeArea()
            }
        }
        // A half-written application is worth more than a tidy gesture, so the
        // swipe is off while there is one and the X asks instead.
        .interactiveDismissDisabled(vm.hasContent && !vm.didSend)
        .confirmationDialog("Discard this application?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep writing", role: .cancel) {}
        } message: {
            Text("Your answers won't be saved.")
        }
        .alert("Mail isn't set up on this iPhone", isPresented: $showNoMailNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            // Short on purpose: SwiftUI truncates a long alert message, and a
            // truncated instruction is no instruction.
            Text("Your answers are copied — paste them into an email to \(RetreatEnquiry.recipient).")
        }
        .alert("That didn't send", isPresented: $showSendFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your answers are still here — try again, or email them to \(RetreatEnquiry.recipient).")
        }
    }

    // MARK: - The form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header

                nameQuestion
                dateOfBirthQuestion
                basedInQuestion
                phoneQuestion
                instagramQuestion
                retreatQuestion
                aboutQuestion
                decisionQuestion
                emailQuestion
                investmentQuestion
                referralQuestion

                submitSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 86)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Join a retreat").sgEyebrow()
            Text("Request a place")
                .font(Theme.headline(32))
                .foregroundStyle(Theme.ink)
                .kerning(-0.3)
            Text("Our groups are kept intentionally small. This form lets us know you a little before we connect on an enrollment call.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPhoto()
        .padding(.bottom, 2)
    }

    // MARK: Questions

    private var nameQuestion: some View {
        question(RetreatEnquiry.Question.name) {
            HStack(spacing: 12) {
                textField("First name", text: $vm.firstName, field: .firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit { focus = .lastName }
                textField("Last name", text: $vm.lastName, field: .lastName)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit { focus = .basedIn }
            }
        }
    }

    private var dateOfBirthQuestion: some View {
        question(RetreatEnquiry.Question.dateOfBirth, help: RetreatEnquiry.Question.dateOfBirthHelp) {
            VStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    focus = nil
                    if vm.dateOfBirth == nil { vm.dateOfBirth = RetreatEnquiryViewModel.defaultDateOfBirth }
                    showDateWheel.toggle()
                } label: {
                    HStack {
                        Text(vm.dateOfBirth.map { $0.formatted(date: .long, time: .omitted) } ?? "Select your date of birth")
                            .font(Theme.body(16))
                            .foregroundStyle(vm.dateOfBirth == nil ? Theme.muted : Theme.ink)
                        Spacer(minLength: 8)
                        Image(systemName: "calendar")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .fieldSurface(active: showDateWheel)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("enquiry-dob")

                if showDateWheel {
                    // Bounded so an under-age date is unreachable rather than
                    // rejected after the fact.
                    DatePicker(
                        RetreatEnquiry.Question.dateOfBirth,
                        selection: Binding(
                            get: { vm.dateOfBirth ?? RetreatEnquiryViewModel.defaultDateOfBirth },
                            set: { vm.dateOfBirth = $0 }
                        ),
                        in: ...RetreatEnquiryViewModel.latestDateOfBirth,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .tint(Theme.honey)
                    .frame(maxWidth: .infinity)
                    .fieldSurface(active: true)
                }
            }
        }
    }

    private var basedInQuestion: some View {
        question(RetreatEnquiry.Question.basedIn) {
            textField("City, country", text: $vm.basedIn, field: .basedIn)
                .textContentType(.addressCity)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .onSubmit { focus = .phone }
        }
    }

    private var phoneQuestion: some View {
        question(RetreatEnquiry.Question.phone, help: RetreatEnquiry.Question.phoneHelp) {
            // One field, country code and all. A country picker would be a
            // second answer to a single question, and the number only has to
            // be dialable by a person — see `isPhoneValid`.
            textField("+34 600 000 000", text: $vm.phone, field: .phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
        }
    }

    private var instagramQuestion: some View {
        question(RetreatEnquiry.Question.instagram, optional: true) {
            textField("@yourhandle", text: $vm.instagram, field: .instagram)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .about }
        }
    }

    private var retreatQuestion: some View {
        question(RetreatEnquiry.Question.retreat) {
            VStack(spacing: 10) {
                ForEach(vm.retreatOptions, id: \.self) { option in
                    choiceRow(option, selected: vm.selectedRetreat == option) {
                        vm.selectedRetreat = option
                    }
                }
            }
        }
    }

    private var aboutQuestion: some View {
        question(RetreatEnquiry.Question.about, help: RetreatEnquiry.Question.aboutHelp) {
            TextEditor(text: $vm.about)
                .focused($focus, equals: .about)
                .font(Theme.body(16))
                .foregroundStyle(Theme.ink)
                .tint(Theme.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 136)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .fieldSurface(active: focus == .about)
                .overlay(alignment: .topLeading) {
                    if vm.about.isEmpty {
                        Text("A few lines is plenty.")
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 17)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier(Field.about.id)
        }
    }

    private var decisionQuestion: some View {
        question(RetreatEnquiry.Question.decision) {
            VStack(spacing: 10) {
                ForEach(RetreatEnquiry.Decision.allCases) { option in
                    choiceRow(option.rawValue, selected: vm.decision == option) {
                        vm.decision = option
                    }
                }
            }
        }
    }

    private var emailQuestion: some View {
        question(RetreatEnquiry.Question.email) {
            textField("you@example.com", text: $vm.email, field: .email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .referral }
        }
    }

    private var investmentQuestion: some View {
        question(RetreatEnquiry.Question.investment) {
            VStack(spacing: 10) {
                ForEach(RetreatEnquiry.Investment.allCases) { option in
                    choiceRow(option.rawValue, selected: vm.investment == option) {
                        vm.investment = option
                    }
                }
            }
        }
    }

    private var referralQuestion: some View {
        question(RetreatEnquiry.Question.referral, optional: true) {
            textField("Their name", text: $vm.referral, field: .referral)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { focus = nil }
        }
    }

    // MARK: - Submit

    private var submitSection: some View {
        VStack(spacing: 12) {
            SGPrimaryButton(title: "Submit", enabled: vm.canSubmit, filled: true) {
                submit()
            }
            .accessibilityIdentifier("enquiry-submit")

            // On a form this long, a dim button with no explanation is a
            // dead end — say which questions are still open.
            if !vm.canSubmit {
                Text("Still to answer — \(vm.missingAnswers.joined(separator: " · "))")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .onPhoto()
                    .accessibilityIdentifier("enquiry-missing")
            }

            Text("Sent to \(RetreatEnquiry.recipient) from your mail app, so our reply comes straight back to you.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .onPhoto()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func submit() {
        focus = nil
        guard let enquiry = vm.makeEnquiry() else { return }

        guard MailComposeView.canSend else {
            // No mail account: the answers are still worth something, so hand
            // them over rather than losing them to a dead end.
            UIPasteboard.general.string = """
            To: \(RetreatEnquiry.recipient)
            Subject: \(enquiry.mailSubject)

            \(enquiry.mailBody)
            """
            showNoMailNotice = true
            return
        }

        composed = enquiry
        showComposer = true
    }

    private func handle(_ outcome: MailComposeView.Outcome) {
        showComposer = false
        switch outcome {
        case .sent:
            Haptics.success()
            vm.didSend = true
        case .cancelled:
            // Back to the form with every answer intact.
            break
        case .failed:
            showSendFailure = true
        }
    }

    // MARK: - Sent

    /// The website's own confirmation copy, so an application sent from the
    /// app is answered in the same voice as one sent from the site.
    private var sentPanel: some View {
        VStack(spacing: 18) {
            Image(systemName: "envelope.open")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.honey)
            VStack(spacing: 14) {
                Text("Thank you for your interest in Soulfull Gatherings.")
                    .font(Theme.headline(26))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.2)
                Text("We read every application personally, because the room matters to us as much as it will to you.\n\nWe will be in touch as new gatherings open that feel right for you. Keep an eye on your inbox and WhatsApp.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(3)
            }
            .multilineTextAlignment(.center)
            .onPhoto()

            SGPrimaryButton(title: "Back to the retreat") { dismiss() }
                .padding(.top, 6)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: 340)
    }

    // MARK: - Chrome

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                CircleIconButton(systemName: "xmark", size: 38) {
                    Haptics.tap()
                    if vm.hasContent && !vm.didSend {
                        confirmDiscard = true
                    } else {
                        dismiss()
                    }
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("enquiry-close")
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    // MARK: - Building blocks

    /// Question title (+ its helper line, + an "optional" marker) over its
    /// control. The title text is the same constant the email body uses.
    private func question<Content: View>(
        _ title: String,
        help: String? = nil,
        optional: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(Theme.body(15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if optional {
                        Text("optional")
                            .font(Theme.eyebrow(9))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                if let help {
                    Text(help)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkOnPhoto)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Copy only — never the field below it.
            .onPhoto()

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textField(_ placeholder: String, text: Binding<String>, field: Field) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Theme.muted))
            .focused($focus, equals: field)
            .font(Theme.body(16))
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .fieldSurface(active: focus == field)
            .accessibilityIdentifier(field.id)
    }

    private func choiceRow(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(selected ? Theme.honey : Theme.inkSoft)
                Text(label)
                    .font(Theme.body(14, weight: selected ? .medium : .regular))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.13 : 0.06))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Theme.honey.opacity(0.55) : Theme.glassBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.soulPressableQuiet)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Field surface

private extension View {
    /// The one glass surface every control on this form sits on. No shadow —
    /// these wrap UIKit-backed views.
    func fieldSurface(active: Bool) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(active ? Theme.glassBorderHigh : Theme.glassBorder, lineWidth: 1)
            )
    }
}

#Preview {
    RetreatEnquiryView(retreat: Retreat.mock.first!, initialName: "Hugo")
}
