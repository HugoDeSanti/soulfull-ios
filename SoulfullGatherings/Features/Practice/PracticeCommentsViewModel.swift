//
//  PracticeCommentsViewModel.swift
//  Soulfull Gatherings
//
//  The conversation under one practice (0032): what members have said,
//  newest first, and this member's own comment on its way. Nothing is
//  invented: the comments are `practice_comment_thread`, and a post is a row
//  on `practice_comments`, which the server checks and may turn down.
//
//  Its page owns it and hands it to the sheet, so both show the same read. It
//  is also the comments' Report and Block (`MemberSafetyActions`): a member
//  blocked here leaves the thread at once and stays out of it, even from a
//  read that set off before the block landed.
//

import SwiftUI

/// Why the conversation has nothing to show, when it isn't that nobody has
/// spoken.
enum CommentsLoadFailure: Equatable {
    case offline
    case failed

    init(offline: Bool) { self = offline ? .offline : .failed }

    var message: String {
        switch self {
        case .offline: "You'll need to be online to read the conversation."
        case .failed:  "The conversation didn't load at our end."
        }
    }
}

/// The reads and writes a conversation makes, and the clock it judges their
/// age by. Injectable so its rules — a reload over what's on screen, a post
/// kept when it fails, a delete or block put back when it's refused, a late
/// read never undoing a write — can be tested without a network
/// (`SoulfullTests/Practice/PracticeCommentsTests`). The app uses `.live`, or
/// `.preview` under `-preview-comments`.
struct PracticeCommentsBackend {
    var currentUserID: @MainActor () -> UUID?
    var fetch: @MainActor (_ thread: CommentThread) async throws -> [PracticeComment]
    var post: @MainActor (_ id: UUID, _ thread: CommentThread, _ body: String, _ userID: UUID) async throws -> Void
    var delete: @MainActor (_ id: UUID) async throws -> Void
    /// Blocks `memberID` on behalf of `userID` (0028).
    var block: @MainActor (_ memberID: UUID, _ userID: UUID) async throws -> Void
    var report: @MainActor (_ report: MemberReport) async throws -> Void
    var now: @MainActor () -> Date

    /// Computed rather than stored, so there is no shared global to make
    /// `Sendable`.
    @MainActor static var live: PracticeCommentsBackend {
        #if DEBUG
        if PracticeCommentsViewModel.isPreview { return .preview }
        #endif
        return PracticeCommentsBackend(
            currentUserID: { SupabaseService.shared.client.auth.currentUser?.id },
            fetch: { try await SupabaseService.shared.fetchComments(on: $0, limit: PracticeCommentsViewModel.readLimit) },
            post: { try await SupabaseService.shared.postComment(id: $0, on: $1, body: $2, userID: $3) },
            delete: { try await SupabaseService.shared.deleteComment(id: $0) },
            block: { try await SupabaseService.shared.blockMember($0, userID: $1) },
            report: { try await SupabaseService.shared.reportMember($0) },
            now: { Date.now }
        )
    }
}

@Observable @MainActor
final class PracticeCommentsViewModel: MemberSafetyActions {

    /// How long a read stays current. Coming back to the page inside it shows
    /// what is there; after it, the page reads again, quietly, over the
    /// comments on screen. The same minute the Community tab allows.
    static let freshFor: TimeInterval = 60

    /// The most one read takes. A thread that fills it reads "200+".
    static let readLimit = 200

    let thread: CommentThread

    /// Newest first.
    private(set) var comments: [PracticeComment] = []
    /// Some read has answered. Before that, "nobody has spoken" isn't known.
    private(set) var hasLoaded = false
    private(set) var loadFailure: CommentsLoadFailure?

    /// What the member is writing. The sheet caps it as it's typed
    /// (`CommentDraft.capped`).
    var draft = ""
    private(set) var isPosting = false
    /// Why the last post didn't go, worded for the writer. What they wrote
    /// stays in `draft`.
    private(set) var postFailure: String?
    /// A delete or block that didn't go, for a line under the list.
    private(set) var actionError: String?
    /// Comments and members with a write in flight, so nothing double-fires.
    private(set) var busy: Set<UUID> = []

    /// Members blocked from here, and this member's comments deleted from
    /// here. The server leaves both out once the write lands; these keep them
    /// off screen meanwhile, including from a read that set off before it.
    private(set) var hiddenMembers: Set<UUID> = []
    private var removed: Set<UUID> = []

    /// The post in flight or last failed, so posting the same words again
    /// sends the same id — a retry after a timeout that had in fact landed is
    /// then a duplicate, not a second comment.
    private var pending: (id: UUID, body: String)?
    private var loadedAt: Date?
    private var reading = false
    /// Bumped by every read and every write. A read only lands if it is the
    /// latest and nothing was written while it was out: a comment posted,
    /// deleted or blocked mid-read must not be undone by the answer.
    @ObservationIgnored private var readSequence = 0
    @ObservationIgnored private var writes = 0

    private let backend: PracticeCommentsBackend

    init(thread: CommentThread, backend: PracticeCommentsBackend = .live) {
        self.thread = thread
        self.backend = backend
    }

    /// `-preview-comments`: the conversation runs against an in-memory
    /// fixture, so the populated page and every action can be seen (and
    /// tested) without posting to the live database. Always false in Release.
    nonisolated static var isPreview: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-preview-comments")
        #else
        false
        #endif
    }

    var count: Int { comments.count }
    var countLabel: String { count >= Self.readLimit ? "\(Self.readLimit)+" : "\(count)" }
    var canPost: Bool { CommentDraft.postable(draft) != nil && !isPosting }

    // MARK: - Reading

    /// Cheap on appear: reads only what is missing, failed, or older than
    /// `freshFor`. A reload keeps the comments on screen; a failed reload over
    /// comments leaves them there and says nothing.
    func load(force: Bool = false) async {
        if !force {
            guard !reading else { return }
            if loadFailure == nil, let loadedAt, backend.now().timeIntervalSince(loadedAt) < Self.freshFor { return }
        }
        readSequence += 1
        let sequence = readSequence, writesAtStart = writes
        reading = true
        defer { if sequence == readSequence { reading = false } }
        do {
            let rows = try await backend.fetch(thread)
            guard sequence == readSequence, writesAtStart == writes else { return }
            comments = rows.filter(isShown)
            hasLoaded = true
            loadFailure = nil
            loadedAt = backend.now()
        } catch where error.isCancellation {
            return
        } catch {
            guard sequence == readSequence else { return }
            Log.data.info("Comments unavailable: \(error.localizedDescription)")
            loadFailure = CommentsLoadFailure(offline: error.isOffline)
        }
    }

    private func isShown(_ comment: PracticeComment) -> Bool {
        !hiddenMembers.contains(comment.author.id) && !removed.contains(comment.id)
    }

    // MARK: - Posting

    /// Sends the draft. On success it leads the list at once and the draft
    /// clears; the server's own copy (the name others see, the guide mark)
    /// replaces it a moment later. On failure the words stay and the reason is
    /// said: what the server refused and why, offline, or our end.
    @discardableResult
    func post() async -> Bool {
        guard let body = CommentDraft.postable(draft), !isPosting,
              let userID = backend.currentUserID() else { return false }
        let id = pending?.body == body ? pending!.id : UUID()
        pending = (id, body)
        isPosting = true
        postFailure = nil
        actionError = nil
        writes += 1
        defer { isPosting = false }
        do {
            try await backend.post(id, thread, body, userID)
        } catch {
            Log.data.error("Comment failed: \(error.localizedDescription)")
            if let refusal = error.commentRefusal {
                // Asked again unchanged, it would say the same: a new id for
                // whatever is written next.
                pending = nil
                postFailure = refusal.message
            } else {
                postFailure = error.isOffline
                    ? "You're offline, so this hasn't been posted. Reconnect and try again — what you wrote is still here."
                    : "This didn't post at our end. Please try again in a moment."
            }
            Haptics.bump()
            return false
        }
        pending = nil
        if draft.trimmingCharacters(in: .whitespacesAndNewlines) == body { draft = "" }
        if !comments.contains(where: { $0.id == id }) {
            let me = CommunityMember(id: userID, displayName: "You", avatarUrl: nil)
            comments.insert(PracticeComment(id: id, author: me, body: body, createdAt: backend.now(),
                                            isMine: true, isGuide: false), at: 0)
        }
        hasLoaded = true
        Haptics.success()
        await load(force: true)
        return true
    }

    // MARK: - Deleting

    /// Deletes one of this member's own comments. Off screen at once; back
    /// only if the server refuses.
    func delete(_ comment: PracticeComment) async {
        guard comment.isMine, !busy.contains(comment.id) else { return }
        busy.insert(comment.id)
        defer { busy.remove(comment.id) }
        actionError = nil
        let before = comments
        removed.insert(comment.id)
        writes += 1
        comments.removeAll { $0.id == comment.id }
        do {
            try await backend.delete(comment.id)
            Haptics.success()
        } catch {
            Haptics.bump()
            Log.data.error("Comment delete failed: \(error.localizedDescription)")
            removed.remove(comment.id)
            comments = before
            actionError = error.isOffline
                ? "You're offline, so your comment is still there. Reconnect and try again."
                : "We couldn't delete your comment just now. Please try again."
        }
    }

    // MARK: - Report and Block

    /// Blocks a comment's author (0028): every comment of theirs leaves the
    /// thread at once and stays out, and the server hides each from the other
    /// everywhere from then on. Put back only if the server refuses.
    @discardableResult
    func block(_ member: CommunityMember) async -> Bool {
        guard let userID = backend.currentUserID(), member.id != userID,
              !busy.contains(member.id) else { return false }
        busy.insert(member.id)
        defer { busy.remove(member.id) }
        actionError = nil
        let before = comments
        hiddenMembers.insert(member.id)
        writes += 1
        comments.removeAll { $0.author.id == member.id }
        do {
            try await backend.block(member.id, userID)
            Haptics.success()
            return true
        } catch {
            Haptics.bump()
            Log.data.error("Block failed: \(error.localizedDescription)")
            hiddenMembers.remove(member.id)
            comments = before
            actionError = error.isOffline
                ? "You're offline, so \(member.displayName) isn't blocked. Reconnect and try again."
                : "We couldn't block \(member.displayName) just now. Please try again."
            return false
        }
    }

    func report(_ report: MemberReport) async throws {
        try await backend.report(report)
    }
}

// MARK: - DEBUG fixture

#if DEBUG
/// `-preview-comments`: every practice's conversation, in memory. A guide's
/// note, two members, and room for "You" — whatever the live tables hold. One
/// store for the whole launch, so a comment posted on a page is there in the
/// player too.
@MainActor
final class PreviewCommentStore {
    static let shared = PreviewCommentStore()

    private var threads: [String: [PracticeComment]] = [:]

    private static func key(_ thread: CommentThread) -> String { "\(thread.kind.rawValue)-\(thread.contentID)" }

    private static func member(_ n: Int, _ name: String) -> CommunityMember {
        CommunityMember(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!,
                        displayName: name, avatarUrl: nil)
    }

    func comments(on thread: CommentThread) -> [PracticeComment] {
        if let held = threads[Self.key(thread)] { return held }
        let now = Date.now
        let seeded = [
            PracticeComment(id: UUID(), author: Self.member(1, "Theo R."),
                            body: "Did this before work and my shoulders came down for the first time all week.",
                            createdAt: now.addingTimeInterval(-2 * 3600), isMine: false, isGuide: false),
            PracticeComment(id: UUID(), author: Self.member(4, "Alma G."),
                            body: "Take the last hold slower than feels necessary. That's where it lands.",
                            createdAt: now.addingTimeInterval(-26 * 3600), isMine: false, isGuide: true),
            PracticeComment(id: UUID(), author: Self.member(2, "Nia K."),
                            body: "Third morning in a row. It gets easier to arrive.",
                            createdAt: now.addingTimeInterval(-4 * 86400), isMine: false, isGuide: false),
        ]
        threads[Self.key(thread)] = seeded
        return seeded
    }

    func post(id: UUID, on thread: CommentThread, body: String) {
        let mine = PracticeComment(id: id, author: CommunityMember(id: InstructorDirectory.previewSelf,
                                                                  displayName: "Hugo D.", avatarUrl: nil),
                                   body: body, createdAt: .now, isMine: true, isGuide: false)
        threads[Self.key(thread)] = [mine] + comments(on: thread)
    }

    func delete(id: UUID) {
        for key in threads.keys { threads[key]?.removeAll { $0.id == id } }
    }

    func block(_ memberID: UUID) {
        for key in threads.keys { threads[key]?.removeAll { $0.author.id == memberID } }
    }
}

extension PracticeCommentsBackend {
    @MainActor static var preview: PracticeCommentsBackend {
        let store = PreviewCommentStore.shared
        return PracticeCommentsBackend(
            currentUserID: { InstructorDirectory.previewSelf },
            fetch: { thread in
                try await Task.sleep(for: .milliseconds(250))
                return store.comments(on: thread)
            },
            post: { id, thread, body, _ in
                try await Task.sleep(for: .milliseconds(400))
                // The server's filter, so the refusal can be seen too.
                if body.localizedCaseInsensitiveContains("http") || body.localizedCaseInsensitiveContains("www.") {
                    throw CommentRefusal.link
                }
                store.post(id: id, on: thread, body: body)
            },
            delete: { id in store.delete(id: id) },
            block: { memberID, _ in store.block(memberID) },
            report: { _ in try await Task.sleep(for: .milliseconds(400)) },
            now: { Date.now }
        )
    }
}
#endif
