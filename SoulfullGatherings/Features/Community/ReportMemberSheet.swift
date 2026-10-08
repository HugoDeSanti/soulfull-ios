//
//  ReportMemberSheet.swift
//  Soulfull Gatherings
//
//  Tell the team about a member: a reason, an optional note, sent through
//  `report-member` (stored, and emailed to the monitored inbox). Then the
//  promise — reviewed within 24 hours — and Block, for not having to see them
//  again in the meantime.
//
//  The note field is UIKit-backed, so nothing here blurs or shades over it
//  (rendering gotcha 1): the backdrop sits behind, and the close bar fades
//  with a gradient, never a blur.
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
        MemberReport(reportedID: member.id, playID: target.playID, reason: reason, details: details)
    }

    var body: some View {
        ScrollView {
            Group {
                if didSend { sent } else { form }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background {
            PhotoBackdrop(imageName: "welcome-bg", blur: 28, darken: 0.86, topScrim: 0)
        }
        .safeAreaInset(edge: .top, spacing: 0) { closeBar }
        .preferredColorScheme(.dark)
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
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text("REPORT")
                    .font(Theme.eyebrow(11))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSoft)
                Text("Report \(member.displayName)")
                    .font(Theme.headline(30))
                    .foregroundStyle(Theme.ink)
                    .kerning(-0.3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Reports are private. \(member.displayName) won't know who sent this.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                AvatarView(avatarUrl: member.avatarUrl, name: member.displayName,
                           seed: member.id.uuidString, size: 44)
                Text(member.displayName)
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(10)
            .soulGlassCard(radius: 18)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 10) {
                Text("What's wrong?")
                    .font(Theme.headline(18))
                    .foregroundStyle(Theme.ink)
                ForEach(ReportReason.allCases) { option in
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
                        .foregroundStyle(Theme.muted)
                }
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
                .soulGlassCard(radius: 16, stroke: noteFocused ? Theme.glassBorderHigh : Theme.glassBorder)
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
                    .soulGlassCard(tint: Theme.honey.opacity(0.06), stroke: Theme.honey.opacity(0.3))
                    .accessibilityIdentifier("report-failure")
                }
                SGPrimaryButton(title: isSending ? "Sending…" : "Send report", enabled: report != nil && !isSending,
                                filled: true) {
                    Task { await submit() }
                }
                .accessibilityIdentifier("report-send")
                Text("\(MemberSafetyCopy.reviewPromise) Anything urgent: \(LegalLinks.supportEmail).")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
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
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(selected ? Theme.honey : Theme.inkSoft)
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
            .soulGlassCard(radius: 16,
                           tint: selected ? Color.white.opacity(0.07) : nil,
                           stroke: selected ? Theme.honey.opacity(0.55) : Theme.glassBorder)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            withAnimation(.easeInOut(duration: 0.3)) { didSend = true }
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
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.honey)
                .padding(.top, 70)
            Text("Thank you")
                .font(Theme.headline(30))
                .foregroundStyle(Theme.ink)
                .kerning(-0.3)
            Text(MemberSafetyCopy.reviewPromise)
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                SGPrimaryButton(title: "Block \(member.displayName)") {
                    onBlock(member)
                    dismiss()
                }
                .accessibilityIdentifier("report-block")
                Text("You won't see each other in Community, and they won't be told.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
            CircleIconButton(systemName: "xmark", size: 38) {
                Haptics.tap()
                dismiss()
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("report-close")
            .disabled(isSending)
            .opacity(isSending ? 0.45 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 14)
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
