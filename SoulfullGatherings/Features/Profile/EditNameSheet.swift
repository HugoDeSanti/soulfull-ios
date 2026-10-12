//
//  EditNameSheet.swift
//  Soulfull Gatherings
//
//  A member changes their name, from the You tab. It lives on their profile,
//  in two parts (`profiles.first_name` / `last_name`, 0033): Home greets them
//  by the first, Community shows it with the last initial ("Mara L."), and a
//  guide linked to the account is named by both everywhere they appear
//  (0027). Without this, a name typed wrong at sign-up, or one Sign in with
//  Apple never shared, stayed that way for good. The date of birth sits under
//  it: asked at email sign-up, but never after Apple, so this is where an
//  Apple member can give one. It is private, and can be changed, not removed.
//
//  Never asked for, only offered: prompting for a name after Sign in with
//  Apple is a rejection pattern (see Onboarding's `asksName`).
//
//  The fields are UIKit-backed, so nothing here blurs or shades over them
//  (rendering gotcha 1); the halo stays on the text.
//

import SwiftUI

@Observable @MainActor
final class EditNameViewModel {

    enum Failure: Equatable {
        case offline
        case failed

        var line: String {
            switch self {
            case .offline: "You're offline, so your name hasn't changed. Reconnect and try again."
            case .failed:  "Something went wrong at our end, and your name hasn't changed. Please try again."
            }
        }
    }

    /// The name as it is now.
    let current: MemberName
    /// What is being typed, each part cut to the limit as it is typed
    /// (`MemberName`).
    var first: String {
        didSet {
            let capped = MemberName.capped(first)
            if capped != first { first = capped }
            if failure != nil, first != oldValue { failure = nil }
        }
    }
    var last: String {
        didSet {
            let capped = MemberName.capped(last)
            if capped != last { last = capped }
            if failure != nil, last != oldValue { failure = nil }
        }
    }
    /// The date of birth as it is now, if one was given.
    let currentBirthDate: BirthDate?
    /// What the wheel has been turned to. Nil until it is, for a member
    /// with no date yet.
    var dateOfBirth: Date? {
        didSet { if failure != nil, dateOfBirth != oldValue { failure = nil } }
    }
    /// The wheel opens on the current date, or `BirthDate.wheelStart`, but
    /// only turning it answers.
    var dateOfBirthWheel: Date {
        get { dateOfBirth ?? BirthDate.wheelStart(now: AppClock.shared.now) }
        set { dateOfBirth = newValue }
    }
    private(set) var isSaving = false
    private(set) var failure: Failure?

    /// Writes the name, and the date when there is one, to the profile and
    /// the phone. Injected so the rules here can be tested without a network
    /// (`SoulfullTests/EditNameTests`).
    private let write: @MainActor (MemberName, BirthDate?) async throws -> Void

    init(current: MemberName, birthDate: BirthDate? = nil,
         write: @escaping @MainActor (MemberName, BirthDate?) async throws -> Void) {
        self.current = current.limited
        self.first = MemberName.capped(current.first)
        self.last = MemberName.capped(current.last)
        self.currentBirthDate = birthDate
        self.dateOfBirth = birthDate?.date()
        self.write = write
    }

    /// The date that would be stored.
    var birthDate: BirthDate? { dateOfBirth.map { BirthDate($0) } }

    /// What would be stored: each part trimmed, and cut to 64 together.
    var name: MemberName { MemberName(first: first, last: last).limited }

    /// Both parts, as at sign-up, and something changed. A blank can't be
    /// saved: the feed would show "A member" and a linked guide's pages would
    /// lose their name. A name from before the parts (one word, or an Apple
    /// account that shared none) is completed here.
    var canSave: Bool {
        MemberName(first: first, last: last).isComplete
            && (name != current || birthDate != currentBirthDate)
            && !isSaving
    }

    /// True once the name is saved.
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        failure = nil
        do {
            try await write(name, birthDate)
            return true
        } catch where error.isCancellation {
            return false
        } catch {
            Log.data.error("Name change failed: \(error.localizedDescription)")
            failure = error.isOffline ? .offline : .failed
            return false
        }
    }
}

struct EditNameSheet: View {
    @State var vm: EditNameViewModel
    /// The member is linked to a guide, whose pages carry this name too.
    var isGuide = false

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    @State private var showDateWheel = false

    private enum Field { case first, last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                fields
                if let failure = vm.failure {
                    Text(failure.line)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .onPhoto()
                        .transition(.opacity)
                        .accessibilityIdentifier("edit-name-failure")
                }
                SGPrimaryButton(title: vm.isSaving ? "Saving…" : "Save",
                                enabled: vm.canSave, filled: true) {
                    Task { await save() }
                }
                .accessibilityIdentifier("edit-name-save")
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 48)
            .animation(Theme.Motion.settle, value: vm.failure)
            .animation(Theme.Motion.settle, value: showDateWheel)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // The Report sheet's ground: home-bg's sky stays too bright under
        // the eyebrow, even this dimmed.
        .background { PhotoBackdrop(imageName: "welcome-bg", blur: 28, darken: 0.86, topScrim: 0) }
        .safeAreaInset(edge: .top, spacing: 0) { closeBar }
        .preferredColorScheme(.dark)
        .presentationCornerRadius(Theme.Corner.sheet)
        .interactiveDismissDisabled(vm.isSaving)
        .onAppear { focus = .first }
        .onChange(of: focus) { _, field in
            if field != nil, showDateWheel { showDateWheel = false }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR DETAILS")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
            Text("What should we call you?")
                .font(Theme.headline(30, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text(explanation)
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(Theme.Motion.settle, value: explanation)
        }
        .onPhoto()
    }

    /// Where the name appears, with the shortened form spelled out as it is
    /// typed — the one place a member can see what everyone else will.
    private var explanation: String {
        let shown = vm.name.shownInCommunity.map { "\u{201C}\($0)\u{201D}" } ?? "your first name and last initial"
        let guide = isGuide ? " Your guide pages use it too." : ""
        return "Other members see \(shown) in Community, and Home greets you by your first name.\(guide) Your date of birth stays private."
    }

    /// The account sheet's two rows: the person glyph on the first, its slot
    /// kept empty on the second so both names start on one line.
    private var fields: some View {
        VStack(spacing: 14) {
            nameField("First name", text: $vm.first, field: .first, glyph: true,
                      contentType: .givenName, identifier: "edit-name-first")
                .submitLabel(.next)
                .onSubmit { focus = .last }
            nameField("Last name", text: $vm.last, field: .last, glyph: false,
                      contentType: .familyName, identifier: "edit-name-last")
                .submitLabel(.done)
                .onSubmit { Task { await save() } }
            dateOfBirthRow
            if showDateWheel { dateOfBirthWheel }
        }
    }

    /// The account sheet's row: the calendar glyph in the slot, the date or
    /// its placeholder, a wheel under it.
    private var dateOfBirthRow: some View {
        Button {
            focus = nil
            showDateWheel.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(vm.birthDate?.formatted ?? "Date of birth")
                    .font(Theme.body(16))
                    .foregroundStyle(vm.birthDate == nil ? Theme.muted : Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .soulGlass(in: Theme.controlShape,
                       stroke: showDateWheel ? Theme.ink.opacity(0.6) : Theme.glassBorder)
        }
        .buttonStyle(.soulPressable)
        .accessibilityLabel("Date of birth")
        .accessibilityValue(vm.birthDate?.formatted ?? "Not set")
        .accessibilityHint("Private, never shown to other members")
        .accessibilityIdentifier("edit-name-dob")
    }

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
    }

    private func nameField(_ placeholder: String, text: Binding<String>, field: Field, glyph: Bool,
                           contentType: UITextContentType, identifier: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Theme.muted)
                .frame(width: 22)
                .opacity(glyph ? 1 : 0)
                .accessibilityHidden(true)
            TextField("", text: text,
                      prompt: Text(placeholder).foregroundStyle(Theme.muted))
                .focused($focus, equals: field)
                .textContentType(contentType)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(Theme.body(16))
                .foregroundStyle(Theme.ink)
                .tint(Theme.ink)
                .accessibilityLabel(placeholder)
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .soulGlass(in: Theme.controlShape,
                   stroke: focus == field ? Theme.ink.opacity(0.6) : Theme.glassBorder)
    }

    private var closeBar: some View {
        HStack {
            Spacer()
            GlyphButton(systemName: "xmark") {
                Haptics.tap()
                dismiss()
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("edit-name-close")
            .disabled(vm.isSaving)
            .opacity(vm.isSaving ? 0.45 : 1)
        }
        // The glyph sits about a gutter from the edge; its 44pt target
        // reaches past it.
        .padding(.horizontal, Theme.gutter - 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [Theme.bg.opacity(0.92), Theme.bg.opacity(0.6), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    private func save() async {
        guard vm.canSave else { return }
        if await vm.save() {
            Haptics.success()
            dismiss()
        } else if vm.failure != nil {
            Haptics.bump()
        }
    }
}
