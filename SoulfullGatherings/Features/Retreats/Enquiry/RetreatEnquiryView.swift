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
//  and posts the finished answers to the `send-retreat-enquiry` Edge Function,
//  which emails them to the monitored inbox. It sends the same way from every
//  device — the earlier version handed the answers to the iPhone's Mail app,
//  which needed Mail configured and needed the applicant to tap Send in a
//  screen they could equally abandon.
//
//  **An account is required to apply**, which `RetreatDetailView` enforces
//  before opening this sheet. That is not a registration wall on browsing —
//  the catalog, the brochure and the whole Practice landing stay open to a
//  guest, so the Guideline 5.1.1(i) argument is unchanged. It is here because
//  the Email answer *is* the account's address: shown, locked, and taken from
//  the JWT server-side rather than typed.
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
    @State private var confirmDiscard = false
    @State private var showDateWheel = false
    @FocusState private var focus: Field?

    private enum Field: String {
        case firstName, lastName, basedIn, phone, instagram, about, referral

        /// Accessibility identifier. Stable names so `RetreatEnquiryTests` can
        /// fill the form without matching on placeholder copy.
        var id: String { "enquiry-\(rawValue)" }

        /// The field after this one, in the order the form asks — where the
        /// keyboard bar's Next goes. Nil for the last.
        var next: Field? {
            switch self {
            case .firstName: .lastName
            case .lastName:  .basedIn
            case .basedIn:   .phone
            case .phone:     .instagram
            case .instagram: .about
            case .about:     .referral
            case .referral:  nil
            }
        }
    }

    /// - Parameters:
    ///   - initialName: the name the phone knows (the account's, or just the
    ///     first name onboarding asked for), seeding the two name fields.
    ///   - initialBirthDate: the account's date of birth, if it has one.
    ///   - accountEmail: the signed-in account's address. Displayed on the
    ///     Email question and never editable — the server stamps the real one
    ///     from the caller's JWT regardless.
    init(retreat: Retreat, initialName: MemberName = MemberName(), initialBirthDate: BirthDate? = nil,
         accountEmail: String = "") {
        self.retreat = retreat
        _vm = State(initialValue: RetreatEnquiryViewModel(
            retreat: retreat, name: initialName, birthDate: initialBirthDate, accountEmail: accountEmail
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
        .presentationCornerRadius(Theme.Corner.sheet)
        // The phone's number pad has no Return key and the About box spends
        // Return on new lines, so neither had a way on or a way out of the
        // keyboard. One bar over every field gives both.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if let next = focus?.next {
                    keyboardButton("Next") { focus = next }
                }
                keyboardButton("Done") { focus = nil }
            }
        }
        .task { await vm.loadOptions() }
        // A half-written application is worth more than a tidy gesture, so the
        // swipe is off while there is one and the X asks instead.
        .interactiveDismissDisabled(vm.hasContent && !vm.didSend)
        .confirmationDialog("Discard this application?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep writing", role: .cancel) {}
        } message: {
            Text("Your answers won't be saved.")
        }
    }

    // MARK: - The form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
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
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 86)
            .padding(.bottom, 56)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Join a retreat").sgEyebrow()
            Text("Request a place")
                .font(Theme.headline(32, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.5)
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
                    // Opens the wheel and nothing more — turning it is what
                    // answers (`dateOfBirthWheel`).
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
                        selection: $vm.dateOfBirthWheel,
                        in: ...RetreatEnquiryViewModel.latestDateOfBirth,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .tint(Theme.ink)
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

    /// Shown, not asked. The address is the one on the account they are signed
    /// in to, and the server reads it from the JWT rather than from anything
    /// sent up here — so an editable field would be a control that changes
    /// nothing. Rendered on the same glass surface as the other answers, at
    /// reduced contrast with a lock, so it reads as an answer already given
    /// rather than a field that has stopped working.
    private var emailQuestion: some View {
        question(RetreatEnquiry.Question.email,
                 help: "The address on your Soulfull account. We'll reply here.") {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Text(vm.accountEmail.isEmpty ? "Your account email" : vm.accountEmail)
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldSurface(active: false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Email, \(vm.accountEmail). From your account, not editable.")
            .accessibilityIdentifier("enquiry-email")
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
            SGPrimaryButton(
                title: vm.isSending ? "Sending…" : "Submit",
                enabled: vm.canSubmit && !vm.isSending,
                filled: true
            ) {
                Task { await submit() }
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

            if let failure = vm.sendFailure {
                errorBanner(failure)
            }

            Text("Sent to \(RetreatEnquiry.recipient), and we'll reply to your account's email.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .onPhoto()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// A veiled panel rather than an alert: a failed send leaves the applicant
    /// on a full form they may want to check, and an alert would cover it and
    /// then need dismissing before they could reach the button again.
    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(Theme.body(13))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .soulGlassCard(stroke: Theme.ember.opacity(0.5))
            .accessibilityIdentifier("enquiry-error")
    }

    private func submit() async {
        focus = nil
        if await vm.send() { Haptics.success() }
    }

    // MARK: - Sent

    /// The website's own confirmation copy, so an application sent from the
    /// app is answered in the same voice as one sent from the site.
    private var sentPanel: some View {
        VStack(spacing: 18) {
            Image(systemName: "envelope.open")
                .font(.system(size: 34, weight: .thin))
                .foregroundStyle(Theme.ember)
            VStack(spacing: 14) {
                Text("Thank you for your interest in Soulfull Gatherings.")
                    .font(Theme.headline(26, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.4)
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
        .accessibilityIdentifier("enquiry-sent")
        .padding(.horizontal, 30)
        .frame(maxWidth: 340)
    }

    // MARK: - Chrome

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                // The press already gives the haptic.
                GlyphButton(systemName: "xmark") {
                    if vm.hasContent && !vm.didSend {
                        confirmDiscard = true
                    } else {
                        dismiss()
                    }
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("enquiry-close")
                // Not while sending: closing then left the send running in a
                // Task nobody was watching, and the application went out from
                // a sheet that had been discarded.
                .disabled(vm.isSending)
                .opacity(vm.isSending ? 0.45 : 1)
            }
            Spacer()
        }
        // The glyph sits inside a 44pt target; this lines the glyph itself
        // up with the gutter.
        .padding(.horizontal, Theme.gutter - 14)
        .padding(.top, 10)
    }

    private func keyboardButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(Theme.body(15, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
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
            HStack(alignment: .top, spacing: 14) {
                // A mark, filled when chosen — no radio circle.
                Theme.markShape
                    .strokeBorder(selected ? Theme.ink : Theme.inkSoft.opacity(0.6), lineWidth: Theme.hairline)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: Theme.Corner.mark / 2, style: .continuous)
                                .fill(Theme.ink).frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top, 1)
                Text(label)
                    .font(Theme.body(14, weight: selected ? .medium : .regular))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.controlShape
                    .fill(Theme.ink.opacity(selected ? 0.06 : 0.02))
                    .background(.ultraThinMaterial, in: Theme.controlShape)
            )
            .overlay(
                Theme.controlShape
                    .strokeBorder(selected ? Theme.ink.opacity(0.7) : Theme.glassBorder, lineWidth: Theme.hairline)
            )
            .contentShape(Rectangle())
            .animation(Theme.Motion.settle, value: selected)
        }
        .buttonStyle(.soulPressableQuiet)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Field surface

private extension View {
    /// The one surface every control on this form sits on. No shadow
    /// and no blur over the field itself — these wrap UIKit-backed views; the
    /// material is a background behind them.
    func fieldSurface(active: Bool) -> some View {
        self
            .background(.ultraThinMaterial, in: Theme.controlShape)
            .overlay(
                Theme.controlShape
                    .strokeBorder(active ? Theme.ink.opacity(0.6) : Theme.glassBorder, lineWidth: Theme.hairline)
            )
    }
}

// Its sample content (`Fixtures.swift`) exists only in DEBUG.
#if DEBUG
#Preview {
    RetreatEnquiryView(retreat: Retreat.mock.first!, initialName: MemberName(first: "Hugo"),
                       accountEmail: "hugo@soulfullgatherings.com")
}
#endif
