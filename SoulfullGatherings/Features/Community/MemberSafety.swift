//
//  MemberSafety.swift
//  Soulfull Gatherings
//
//  Report and Block, wherever another member appears: a line of the feed, a
//  search result, a request, a friend, a like. App Store Guideline 1.2 asks an
//  app whose members can see each other's names and photos for both, and for
//  a timely response — the server half is 0028 and `report-member`; the
//  runbook is docs/MODERATION.md.
//
//  One "⋯" menu on every member row, and one host modifier per screen that
//  owns the two things the menu raises: the Block confirmation and the Report
//  sheet. Reporting is open to a guest (anyone who can see the feed can report
//  what's in it); blocking needs an account, because a block has to outlive
//  the session that made it and a guest is disposable (0023).
//

import SwiftUI

/// Who is being reported, and the feed line it came from, if any.
struct ReportTarget: Identifiable, Hashable {
    let member: CommunityMember
    var playID: UUID? = nil
    var id: UUID { member.id }
}

/// "⋯" beside another member: Report, and Block. Never beside yourself.
struct MemberSafetyMenu: View {
    let member: CommunityMember
    let onReport: () -> Void
    let onBlock: () -> Void

    var body: some View {
        Menu {
            Button {
                onReport()
            } label: {
                Label("Report \(member.displayName)", systemImage: "flag")
            }
            Button(role: .destructive) {
                onBlock()
            } label: {
                Label("Block \(member.displayName)", systemImage: "hand.raised")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                // A 44pt target around a glyph that draws a fraction of it
                // (rendering gotcha 5).
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More for \(member.displayName)")
        .accessibilityHint("Report or block")
        .accessibilityIdentifier("member-menu")
    }
}

extension View {
    /// Hosts the Block confirmation and the Report sheet that `MemberSafetyMenu`
    /// raises on this screen. Set `blocking` to ask, `reporting` to open the
    /// sheet; both clear themselves.
    func memberSafety(vm: CommunityViewModel,
                      reporting: Binding<ReportTarget?>,
                      blocking: Binding<CommunityMember?>,
                      isMember: Bool,
                      requireAccount: @escaping (@escaping () -> Void) -> Void) -> some View {
        modifier(MemberSafetyHost(vm: vm, reporting: reporting, blocking: blocking,
                                  isMember: isMember, requireAccount: requireAccount))
    }
}

private struct MemberSafetyHost: ViewModifier {
    @Bindable var vm: CommunityViewModel
    @Binding var reporting: ReportTarget?
    @Binding var blocking: CommunityMember?
    let isMember: Bool
    let requireAccount: (@escaping () -> Void) -> Void

    /// Chosen inside the Report sheet, acted on once it has gone: a guest's
    /// block goes through the account sheet, which can't rise over this one.
    @State private var blockAfterReport: CommunityMember?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(blocking.map { "Block \($0.displayName)?" } ?? "Block",
                                isPresented: Binding(get: { blocking != nil },
                                                     set: { if !$0 { blocking = nil } }),
                                titleVisibility: .visible,
                                presenting: blocking) { member in
                Button("Block", role: .destructive) {
                    Task { await vm.block(member) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(MemberSafetyCopy.blockExplanation)
            }
            .sheet(item: $reporting, onDismiss: blockChosenInSheet) { target in
                ReportMemberSheet(target: target,
                                  send: { try await vm.report($0) },
                                  onBlock: { blockAfterReport = $0 })
            }
    }

    /// The sheet's "Block" is already an explicit choice with the
    /// consequences spelled out beside it, so a member's goes straight
    /// through; a guest signs in first and then confirms.
    private func blockChosenInSheet() {
        guard let member = blockAfterReport else { return }
        blockAfterReport = nil
        if isMember {
            Task { await vm.block(member) }
        } else {
            requireAccount { blocking = member }
        }
    }
}

/// The words Block and Report use, in one place so the menu, the dialog and
/// the sheet never disagree about what happens.
enum MemberSafetyCopy {
    static let blockExplanation =
        "You won't see each other anywhere in Community — practices, likes, requests or search — and any friendship between you ends. They won't be told. You can unblock them from the You tab."

    static let reviewPromise =
        "Our team reviews every report within 24 hours and removes anything that breaks our community standards."
}
