//
//  ReportMemberSheet.swift
//  Soulfull Gatherings
//
//  Tell the team about a member, or about a comment they wrote under a
//  practice: a reason, an optional note, sent through
//  `report-member` (stored, and emailed to the monitored inbox). Then the
//  promise — reviewed within 24 hours — and Block, for not having to see them
//  again in the meantime.
//
//  The note field is UIKit-backed, so nothing here blurs or shades over it
//  (rendering gotcha 1): the photo sits behind, the halo on the copy stays on
//  the copy, and the close bar fades with a gradient, never a blur.
//

import SwiftUI

struct ReportMemberSheet: View {
    let target: ReportTarget
    let send: (MemberReport) async throws -> Void
    /// "Block" after sending. The host acts on it once this sheet has gone.
    let onBlock: (CommunityMember) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var failure: String?
    @FocusState private var noteFocused: Bool

    private var member: CommunityMember { target.member }
    private var report: MemberReport? {
        MemberReport(reportedID: member.id, playID: target.playID, commentID: target.comment?.id,
                     reason: reason, details: details)
    }

    var body: some View {
        ScrollView {
            Group {
                if didSend { sent } else { form }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { PhotoBackdrop(imageName: "welcome-bg", blur: 28, darken: 0.86, topScrim: 0) }
        .safeAreaInset(edge: .top, spacing: 0) { closeBar }
        .preferredColorScheme(.dark)
        .presentationCornerRadius(Theme.Corner.sheet)
        // A half-written report is worth the extra tap.
        .interactiveDismissDisabled(isSending)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { noteFocused = false }
                    .font(Theme.body(15, weight: .medium))
            }
        }
    }

    // MARK: - Writing

    private var form: some View {
        VStack(alignment: .leading, spacing: 36) {
            VStack(alignment: .leading, spacing: 10) {
                Text("REPORT")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)
                Text(target.comment == nil ? "Report \(member.displayName)" : "Report this comment")
                    .font(Theme.headline(30, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Reports are private. \(member.displayName) won't know who sent this.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onPhoto()

            HStack(alignment: target.comment == nil ? .center : .top, spacing: 12) {
                AvatarView(avatarUrl: member.avatarUrl, name: member.displayName,
                           seed: member.id.uuidString, size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(member.displayName)
                        .font(Theme.body(15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    // What they wrote, as the team will read it.
                    if let comment = target.comment {
                        Text(comment.body)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.inkOnPhoto)
                            .lineSpacing(3)
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .onPhoto()
                Spacer(minLength: 0)
            }
            // Who this is about, between two rules — not a card.
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 10) {
                Text("What's wrong?")
                    .font(Theme.headline(18))
                    .foregroundStyle(Theme.ink)
                    .onPhoto()
                ForEach(target.reasons) { option in
                    reasonRow(option)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Anything we should know?")
                        .font(Theme.headline(18))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("OPTIONAL")
                        .font(Theme.eyebrow(10))
                        .tracking(1.6)
                        .foregroundStyle(Theme.inkSoft)
                }
                // The halo stays on these two labels: the note below is a
                // UIKit-backed TextEditor (gotcha 1).
                .onPhoto()
                TextEditor(text: Binding(
                    get: { details },
                    set: { details = String($0.prefix(MemberReport.maxDetails)) }
                ))
                .focused($noteFocused)
                .font(Theme.body(15))
                .foregroundStyle(Theme.ink)
                .tint(Theme.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .soulGlass(in: Theme.controlShape, stroke: noteFocused ? Theme.glassBorderHigh : Theme.glassBorder)
                .overlay(alignment: .topLeading) {
                    if details.isEmpty {
                        Text("A few words help us act faster.")
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Anything we should know? Optional")
                .accessibilityIdentifier("report-details")
            }

            VStack(alignment: .leading, spacing: 12) {
                if let failure {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 13, weight: .medium))
                        Text(failure)
                            .font(Theme.body(13))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .soulGlass(in: Theme.controlShape, stroke: Theme.ember.opacity(0.35))
                    .accessibilityIdentifier("report-failure")
                }
                SGPrimaryButton(title: isSending ? "Sending…" : "Send report", enabled: report != nil && !isSending,
                                filled: true) {
                    Task { await submit() }
                }
                .accessibilityIdentifier("report-send")
                Text("\(MemberSafetyCopy.reviewPromise) Anything urgent: \(LegalLinks.supportEmail).")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .onPhoto()
            }
        }
        .padding(.top, 4)
    }

    private func reasonRow(_ option: ReportReason) -> some View {
        let selected = reason == option
        return Button {
            Haptics.select()
            reason = option
        } label: {
            HStack(spacing: 14) {
                // A boxed mark, filled when chosen — no radio circle.
                Theme.markShape
                    .strokeBorder(selected ? Theme.ink : Theme.inkSoft.opacity(0.6), lineWidth: Theme.hairline)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: Theme.Corner.mark / 2, style: .continuous)
                                .fill(Theme.ink).frame(width: 8, height: 8)
                        }
                    }
                    .accessibilityHidden(true)
                Text(option.title)
                    .font(Theme.body(14, weight: selected ? .medium : .regular))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .soulGlass(in: Theme.controlShape, stroke: selected ? Theme.ink.opacity(0.7) : Theme.glassBorder)
            .contentShape(Rectangle())
            .animation(Theme.Motion.settle, value: selected)
        }
        .buttonStyle(.soulPressableQuiet)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("report-reason-\(option.rawValue)")
    }

    private func submit() async {
        guard let report, !isSending else { return }
        noteFocused = false
        isSending = true
        failure = nil
        defer { isSending = false }
        do {
            try await send(report)
            Haptics.success()
            withAnimation(Theme.Motion.settle) { didSend = true }
        } catch {
            Haptics.bump()
            Log.data.error("Report failed: \(error.localizedDescription)")
            // What was written stays; the button is the retry.
            failure = error.isOffline
                ? "You're offline, so this hasn't been sent. Reconnect and try again — what you wrote is still here."
                : "This didn't send at our end. Please try again, or email \(LegalLinks.supportEmail)."
        }
    }

    // MARK: - Sent

    private var sent: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(Theme.ember)
                .padding(.top, 80)
            Text("Thank you")
                .font(Theme.headline(30, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.6)
                .onPhoto()
            Text(MemberSafetyCopy.reviewPromise)
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .onPhoto()

            VStack(spacing: 10) {
                SGPrimaryButton(title: "Block \(member.displayName)") {
                    onBlock(member)
                    dismiss()
                }
                .accessibilityIdentifier("report-block")
                Text("You won't see each other in Community or in comments, and they won't be told.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .onPhoto()
            }
            .padding(.top, 18)

            SGPrimaryButton(title: "Done", filled: true) { dismiss() }
                .accessibilityIdentifier("report-done")
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chrome

    private var closeBar: some View {
        HStack {
            Spacer()
            GlyphButton(systemName: "xmark") {
                Haptics.tap()
                dismiss()
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("report-close")
            .disabled(isSending)
            .opacity(isSending ? 0.45 : 1)
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
}

#Preview {
    ReportMemberSheet(target: ReportTarget(member: CommunityMember(id: UUID(), displayName: "Theo R.", avatarUrl: nil)),
                      send: { _ in try await Task.sleep(for: .seconds(1)) },
                      onBlock: { _ in })
}
