//
//  EditNameSheet.swift
//  Soulfull Gatherings
//
//  A member changes their name, from the You tab. It lives on their profile
//  (`profiles.full_name`): Home greets them by its first word, Community shows
//  it shortened ("Mara L."), and a guide linked to the account is named by it
//  everywhere they appear (0027). Without this, a name typed wrong at sign-up,
//  or one Sign in with Apple never shared, stayed that way for good.
//
//  Never asked for, only offered: prompting for a name after Sign in with
//  Apple is a rejection pattern (see Onboarding's `asksName`).
//
//  The field is UIKit-backed, so nothing here blurs or shades over it
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
    let current: String
    /// What is being typed, cut to the limit as it is typed (`MemberName`).
    var draft: String {
        didSet {
            let capped = MemberName.capped(draft)
            if capped != draft { draft = capped }
            if failure != nil, draft != oldValue { failure = nil }
        }
    }
    private(set) var isSaving = false
    private(set) var failure: Failure?

    /// Writes the name to the profile and the phone. Injected so the rules
    /// here can be tested without a network (`SoulfullTests/EditNameTests`).
    private let write: @MainActor (String) async throws -> Void

    init(current: String, write: @escaping @MainActor (String) async throws -> Void) {
        self.current = current
        self.draft = MemberName.capped(current)
        self.write = write
    }

    /// What would be stored: trimmed, and cut to 64.
    var name: String { MemberName.limited(draft) }

    /// A name, and a different one. A blank can't be saved: the feed would
    /// show "A member" and a linked guide's pages would lose their name.
    var canSave: Bool { !name.isEmpty && name != current && !isSaving }

    /// True once the name is saved.
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        failure = nil
        do {
            try await write(name)
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
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                field
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
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // The Report sheet's ground: home-bg's sky stays too bright under
        // the eyebrow, even this dimmed.
        .background { PhotoBackdrop(imageName: "welcome-bg", blur: 28, darken: 0.86, topScrim: 0) }
        .safeAreaInset(edge: .top, spacing: 0) { closeBar }
        .preferredColorScheme(.dark)
        .presentationCornerRadius(0)
        .interactiveDismissDisabled(vm.isSaving)
        .onAppear { focused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR NAME")
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
        let shown = MemberName.shownInCommunity(vm.name).map { "\u{201C}\($0)\u{201D}" } ?? "your first name and last initial"
        let guide = isGuide ? " Your guide pages use it too." : ""
        return "Other members see \(shown) in Community, and Home greets you by your first name.\(guide)"
    }

    private var field: some View {
        HStack(spacing: 12) {
            Image(systemName: "person")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Theme.muted)
                .frame(width: 22)
                .accessibilityHidden(true)
            TextField("", text: $vm.draft,
                      prompt: Text("Your name").foregroundStyle(Theme.muted))
                .focused($focused)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { Task { await save() } }
                .font(Theme.body(16))
                .foregroundStyle(Theme.ink)
                .tint(Theme.ink)
                .accessibilityLabel("Your name")
                .accessibilityIdentifier("edit-name-field")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .soulGlass(in: Rectangle(),
                   stroke: focused ? Theme.ink.opacity(0.6) : Theme.glassBorder)
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
