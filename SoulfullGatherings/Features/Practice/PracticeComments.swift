//
//  PracticeComments.swift
//  Soulfull Gatherings
//
//  What members say under a practice (0032). A movement sequence and a recipe
//  end with the newest two comments and a way into the rest
//  (`PracticeCommentsSection`); the player offers the same under the title
//  (`PracticeCommentsLink`). Both open one sheet: the practice's photograph,
//  a box to write in, and every comment, newest first.
//
//  Every comment carries a "⋯": Report and Block for someone else's
//  (Guideline 1.2, the same tools the feed has), Delete for your own. Journal
//  prompts have no comments (`PracticeContentKind.takesComments`).
//
//  Practice pages open for a member only (`AccountGate`), so nothing here
//  meets a guest; the server refuses one anyway.
//
//  The writing box is UIKit-backed, so nothing here blurs or shades over it
//  (rendering gotcha 1): the halo stays on the copy around it.
//

import SwiftUI

// MARK: - On a practice page

/// The foot of a practice page: a rule, "COMMENTS" and the count, the newest
/// two, and a way into the rest. It owns the conversation and hands it to the
/// sheet, so the two always agree.
struct PracticeCommentsSection: View {
    @State private var vm: PracticeCommentsViewModel
    @State private var showingAll = false
    @State private var reporting: ReportTarget?
    @State private var blocking: CommunityMember?

    /// How many of the newest the page shows; the rest are one tap away.
    static let shownOnPage = 2

    init(thread: CommentThread) {
        _vm = State(initialValue: PracticeCommentsViewModel(thread: thread))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CommentsHeading(count: vm.hasLoaded ? vm.count : nil, countLabel: vm.countLabel)
                .padding(.bottom, 4)

            if !vm.hasLoaded {
                if let failure = vm.loadFailure {
                    CommentsLoadFailureLine(failure: failure) { Task { await vm.load(force: true) } }
                        .padding(.vertical, 16)
                } else {
                    ProgressView()
                        .tint(Theme.inkSoft)
                        .padding(.vertical, 20)
                }
            } else {
                if vm.comments.isEmpty {
                    Text("Nobody has shared yet. How did it go?")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.inkOnPhoto)
                        .lineSpacing(3)
                        .onPhoto()
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                } else {
                    ForEach(vm.comments.prefix(Self.shownOnPage)) { comment in
                        CommentRow(comment: comment, bodyLineLimit: 4, identifier: "comment-preview",
                                   onReport: { reporting = ReportTarget(member: comment.author, comment: comment) },
                                   onBlock: { blocking = comment.author },
                                   onDelete: { Task { await vm.delete(comment) } })
                            .transition(.opacity)
                    }
                }
                openButton
            }

            if let actionError = vm.actionError {
                CommentsNote(text: actionError)
                    .padding(.top, 12)
            }
        }
        .animation(Theme.Motion.settle, value: vm.comments.map(\.id))
        .animation(Theme.Motion.settle, value: vm.hasLoaded)
        .task { await vm.load() }
        .sheet(isPresented: $showingAll) { PracticeCommentsSheet(vm: vm) }
        .memberSafety(vm: vm, reporting: $reporting, blocking: $blocking,
                      isMember: true, requireAccount: { $0() })
    }

    /// Into the sheet: to write, or to read the rest.
    private var openButton: some View {
        Button {
            showingAll = true
        } label: {
            HStack(spacing: 12) {
                Text(openLabel)
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Theme.inkSoft)
            }
            .onPhoto()
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.soulPressable)
        .overlay(alignment: .top) { PracticeRule() }
        .overlay(alignment: .bottom) { PracticeRule() }
        .accessibilityIdentifier("comments-open")
    }

    private var openLabel: String {
        switch vm.count {
        case 0:                    "Be the first to share how it went"
        case ...Self.shownOnPage:  "Add a comment"
        default:                   "Read all \(vm.countLabel) comments"
        }
    }
}

// MARK: - In the player

/// "COMMENTS · 12" under a session's title, opening the same sheet as a page.
/// Audio carries on underneath while it's open.
struct PracticeCommentsLink: View {
    @State private var vm: PracticeCommentsViewModel
    @State private var showingAll = false

    init(thread: CommentThread) {
        _vm = State(initialValue: PracticeCommentsViewModel(thread: thread))
    }

    var body: some View {
        Button {
            showingAll = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12, weight: .light))
                Text(vm.count > 0 ? "COMMENTS · \(vm.countLabel)" : "COMMENTS")
                    .font(Theme.eyebrow(10))
                    .tracking(2)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 14)
            // A 44pt target around a small caps line (rendering gotcha 5).
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .animation(Theme.Motion.settle, value: vm.count)
        }
        .buttonStyle(.soulPressable)
        .accessibilityLabel(vm.count == 1 ? "Comments, 1 comment"
                            : vm.count > 0 ? "Comments, \(vm.countLabel) comments" : "Comments")
        .accessibilityIdentifier("comments-link")
        .task { await vm.load() }
        .sheet(isPresented: $showingAll) { PracticeCommentsSheet(vm: vm) }
    }
}

// MARK: - The sheet

/// Every comment on one practice, and the box to add yours, on the practice's
/// own photograph.
struct PracticeCommentsSheet: View {
    let vm: PracticeCommentsViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var writing: Bool
    @State private var reporting: ReportTarget?
    @State private var blocking: CommunityMember?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 28)
                composer
                    .padding(.bottom, 36)
                list
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { PhotoBackdrop(imageName: vm.thread.imageUrl, blur: 28, darken: 0.84, topScrim: 0) }
        .safeAreaInset(edge: .top, spacing: 0) { closeBar }
        .preferredColorScheme(.dark)
        .presentationCornerRadius(0)
        // Words on their way are worth the extra tap.
        .interactiveDismissDisabled(vm.isPosting)
        .animation(Theme.Motion.settle, value: vm.comments.map(\.id))
        .animation(Theme.Motion.settle, value: vm.postFailure)
        .task { await vm.load() }
        .memberSafety(vm: vm, reporting: $reporting, blocking: $blocking,
                      isMember: true, requireAccount: { $0() })
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { writing = false }
                    .font(Theme.body(15, weight: .medium))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMMENTS")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
            Text(vm.thread.title)
                .font(Theme.headline(30, weight: .light))
                .foregroundStyle(Theme.ink)
                .kerning(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("What members noticed, in their own words. Every member can read what you post here.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPhoto()
    }

    // MARK: Writing

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: Binding(get: { vm.draft }, set: { vm.draft = CommentDraft.capped($0) }),
                      prompt: Text("How did it go?").foregroundStyle(Theme.muted),
                      axis: .vertical)
                .lineLimit(2...8)
                .font(Theme.body(15))
                .foregroundStyle(Theme.ink)
                .tint(Theme.ink)
                .focused($writing)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .soulGlassCard(stroke: writing ? Theme.glassBorderHigh : Theme.glassBorder)
                .accessibilityLabel("Your comment")
                .accessibilityIdentifier("comment-field")

            HStack(alignment: .center, spacing: 12) {
                Text(footnote)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .onPhoto()
                Spacer(minLength: 0)
                postButton
            }

            if let failure = vm.postFailure {
                CommentsNote(text: failure)
                    .accessibilityIdentifier("comment-failure")
                    .transition(.opacity)
            }
        }
    }

    /// The community standard, until the limit is close; then what's left.
    private var footnote: String {
        let left = CommentDraft.remaining(vm.draft)
        return left < 60 ? "\(left) characters left" : "Kind words only. Links can't be posted."
    }

    private var postButton: some View {
        let ready = vm.canPost
        return Button {
            Haptics.bump()
            Task {
                if await vm.post() { writing = false }
            }
        } label: {
            Text(vm.isPosting ? "Posting…" : "Post")
                .font(Theme.body(14, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(ready ? Color.black : Theme.ink)
                .padding(.horizontal, 24)
                .frame(minHeight: 44)
                .background(
                    Rectangle()
                        .fill(ready ? Theme.ink : Color.clear)
                        .overlay(Rectangle().strokeBorder(Theme.ink.opacity(0.7),
                                                          lineWidth: ready ? 0 : Theme.hairline))
                )
                .opacity(ready || vm.isPosting ? 1 : 0.4)
                .contentShape(Rectangle())
                .animation(Theme.Motion.settle, value: ready)
        }
        .buttonStyle(SoulPressableStyle(hapticOnPress: false))
        .disabled(!ready)
        .accessibilityIdentifier("comment-post")
    }

    // MARK: Reading

    @ViewBuilder
    private var list: some View {
        if !vm.hasLoaded {
            if let failure = vm.loadFailure {
                CommentsLoadFailureLine(failure: failure) { Task { await vm.load(force: true) } }
            } else {
                ProgressView()
                    .tint(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            }
        } else if vm.comments.isEmpty {
            Text("Nobody has shared yet. Yours could be the first.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkOnPhoto)
                .onPhoto()
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(vm.comments) { comment in
                    CommentRow(comment: comment,
                               onReport: { reporting = ReportTarget(member: comment.author, comment: comment) },
                               onBlock: { blocking = comment.author },
                               onDelete: { Task { await vm.delete(comment) } })
                        .transition(.opacity)
                }
                PracticeRule()
            }
        }
        if let actionError = vm.actionError {
            CommentsNote(text: actionError)
                .padding(.top, 16)
        }
    }

    // MARK: Chrome

    private var closeBar: some View {
        HStack {
            Spacer()
            GlyphButton(systemName: "xmark") {
                Haptics.tap()
                dismiss()
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("comments-close")
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

// MARK: - Pieces

/// "COMMENTS · 12", the count in ember once it's known.
private struct CommentsHeading: View {
    /// Nil until the first read answers.
    let count: Int?
    let countLabel: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("COMMENTS")
                .font(Theme.eyebrow(11))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)
            if let count, count > 0 {
                Text(countLabel)
                    .font(Theme.eyebrow(11))
                    .tracking(1.5)
                    .foregroundStyle(Theme.ember)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .onPhoto()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("comments-heading")
    }

    private var spoken: String {
        switch count {
        case nil, 0?: "Comments"
        case 1?:      "Comments, 1 comment"
        default:      "Comments, \(countLabel) comments"
        }
    }
}

/// One comment: a face, the name (or "You"), a guide's mark, when, and what
/// they said — an open row between hairlines, ending in its "⋯".
struct CommentRow: View {
    let comment: PracticeComment
    /// The page shows a few lines; the sheet shows all of it.
    var bodyLineLimit: Int? = nil
    /// The page's rows and the sheet's are told apart: the page stays in the
    /// accessibility tree under the sheet.
    var identifier = "comment-row"
    var onReport: () -> Void = {}
    var onBlock: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var confirmingDelete = false

    private var name: String { comment.isMine ? "You" : comment.author.displayName }
    private var when: String { RelativeTime.label(comment.createdAt, now: AppClock.shared.now) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(avatarUrl: comment.author.avatarUrl, name: comment.author.displayName,
                       seed: comment.author.id.uuidString, size: 32)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(Theme.body(14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if comment.isGuide {
                        Text("GUIDE")
                            .font(Theme.eyebrow(9))
                            .tracking(1.8)
                            .foregroundStyle(Theme.ember)
                    }
                    Text(when.uppercased())
                        .font(Theme.eyebrow(9))
                        .tracking(1.4)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                Text(comment.body)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.inkOnPhoto)
                    .lineSpacing(3)
                    .lineLimit(bodyLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onPhoto()
            .frame(maxWidth: .infinity, alignment: .leading)

            CommentMenu(comment: comment, onReport: onReport, onBlock: onBlock,
                        onDelete: { confirmingDelete = true })
                // The dots sit by the name; the 44pt target reaches past them.
                .padding(.top, -12)
                .padding(.trailing, -12)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { PracticeRule() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name)\(comment.isGuide ? ", guide" : ""), \(when). \(comment.body)")
        .accessibilityIdentifier(identifier)
        .confirmationDialog("Delete your comment?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's removed for everyone. This can't be undone.")
        }
    }
}

/// "⋯" on a comment: Report and Block for someone else's, Delete for yours.
private struct CommentMenu: View {
    let comment: PracticeComment
    let onReport: () -> Void
    let onBlock: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            if comment.isMine {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete comment", systemImage: "trash")
                }
            } else {
                Button(action: onReport) {
                    Label("Report comment", systemImage: "flag")
                }
                Button(role: .destructive, action: onBlock) {
                    Label("Block \(comment.author.displayName)", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(comment.isMine ? "More for your comment" : "More for \(comment.author.displayName)'s comment")
        .accessibilityHint(comment.isMine ? "Delete" : "Report or block")
        .accessibilityIdentifier("comment-menu")
    }
}

/// The conversation couldn't be read, before anything was: why, and again.
private struct CommentsLoadFailureLine: View {
    let failure: CommentsLoadFailure
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(failure.message)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkOnPhoto)
                .fixedSize(horizontal: false, vertical: true)
                .onPhoto()
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                retry()
            } label: {
                Text("Try again")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .underline(true, color: Theme.ink.opacity(0.5))
                    .onPhoto()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.soulPressableQuiet)
        }
        .accessibilityIdentifier("comments-failure")
    }
}

/// Why something didn't go — a post, a delete, a block. The words stay where
/// they were; this says what happened.
private struct CommentsNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .medium))
            Text(text)
                .font(Theme.body(13))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .soulGlassCard(stroke: Theme.ember.opacity(0.35))
    }
}
