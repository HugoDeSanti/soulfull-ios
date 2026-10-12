//
//  PracticeCommentsTests.swift
//  SoulfullTests
//
//  Comments under a practice (0032), as the app holds them: what a draft may
//  be, which practices take comments, how a refusal is worded, and the
//  conversation's rules — a reload over what's on screen, a post kept when it
//  fails and retried under the same id, a delete or block put back when it's
//  refused, a block that holds against a late read, and a read that set off
//  before a write never undoing it. The server's side (RLS, the trigger, the
//  thread view) is verified live per 0032's header; the screens are
//  SoulfullUITests/PracticeCommentsTests.
//

import Foundation
import Testing
@preconcurrency import Supabase
@testable import SoulfullGatherings

@MainActor
final class FakeComments {
    var now = Calendar.gregorian(in: "Europe/Madrid").at(2026, 10, 12, 12)
    var me: UUID? = UUID()
    /// What the server holds: what a read answers.
    var rows: [PracticeComment] = []
    var fetchError: (any Error)?
    /// What the next post, delete, block or report throws, if anything.
    var writeError: (any Error)?
    /// Holds the next read after it has taken its answer, until `release()`.
    var holdNextRead = false

    private(set) var reads = 0
    /// Every post sent, landed or not.
    private(set) var attempts: [(id: UUID, body: String)] = []
    /// The posts that landed.
    private(set) var posted: [(id: UUID, body: String)] = []
    private(set) var deleted: [UUID] = []
    private(set) var blocked: [UUID] = []
    private(set) var reports: [MemberReport] = []
    private var gate: CheckedContinuation<Void, Never>?

    static let thread = CommentThread(Fixtures.exercise(1))

    func viewModel() -> PracticeCommentsViewModel {
        PracticeCommentsViewModel(thread: Self.thread, backend: PracticeCommentsBackend(
            currentUserID: { self.me },
            fetch: { _ in
                self.reads += 1
                let answer = self.rows
                if self.holdNextRead {
                    self.holdNextRead = false
                    await withCheckedContinuation { self.gate = $0 }
                }
                if let error = self.fetchError { throw error }
                return answer
            },
            post: { id, _, body, userID in
                self.attempts.append((id, body))
                if let error = self.writeError { throw error }
                self.posted.append((id, body))
                self.rows.insert(PracticeComment(id: id, author: CommunityMember(id: userID, displayName: "Hugo D.", avatarUrl: nil),
                                                 body: body, createdAt: self.now, isMine: true, isGuide: false), at: 0)
            },
            delete: { id in
                if let error = self.writeError { throw error }
                self.deleted.append(id)
                self.rows.removeAll { $0.id == id }
            },
            block: { memberID, _ in
                if let error = self.writeError { throw error }
                self.blocked.append(memberID)
            },
            report: { report in
                if let error = self.writeError { throw error }
                self.reports.append(report)
            },
            now: { self.now }
        ))
    }

    /// A read is waiting at the gate.
    var isHoldingRead: Bool { gate != nil }

    func release() {
        gate?.resume()
        gate = nil
    }

    func wait(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }

    func member(_ name: String) -> CommunityMember {
        CommunityMember(id: UUID(), displayName: name, avatarUrl: nil)
    }

    func comment(by author: CommunityMember, _ body: String = "Lovely", mine: Bool = false) -> PracticeComment {
        PracticeComment(id: UUID(), author: author, body: body, createdAt: now, isMine: mine, isGuide: false)
    }

    func myComment(_ body: String = "Mine") -> PracticeComment {
        comment(by: CommunityMember(id: me!, displayName: "Hugo D.", avatarUrl: nil), body, mine: true)
    }
}

// MARK: - The draft and the rules

@MainActor
@Suite("Comment drafts")
struct CommentDraftTests {

    @Test func whatIsSentIsTrimmedAsTheServerTrimsIt() {
        #expect(CommentDraft.postable("  \n Felt lighter after.\n ") == "Felt lighter after.")
    }

    @Test(arguments: ["", "   ", "\n\n\t "])
    func nothingButSpaceIsNotAComment(_ text: String) {
        #expect(CommentDraft.postable(text) == nil)
    }

    @Test func theLimitIsFiveHundredCodePointsAsPostgresCountsThem() {
        let exactly = String(repeating: "a", count: CommentDraft.maxLength)
        let over = exactly + "a"
        // 👋🏽 is two scalars (a hand and a skin tone), one Character.
        let emoji = String(repeating: "👋🏽", count: CommentDraft.maxLength / 2)

        #expect(CommentDraft.postable(exactly) == exactly)
        #expect(CommentDraft.postable(over) == nil)
        #expect(CommentDraft.postable(emoji) == emoji)
        #expect(CommentDraft.postable(emoji + "a") == nil)
    }

    @Test func typingStopsAtTheLimitWithoutSplittingACharacter() {
        let almost = String(repeating: "a", count: CommentDraft.maxLength - 1)

        let capped = CommentDraft.capped(almost + "👋🏽b")

        #expect(capped == almost)
        #expect(CommentDraft.remaining(capped) == 1)
    }

    @Test func journalPromptsTakeNoComments() {
        let journal = CommentThread(kind: .journal, contentID: 1, title: "Prompt", imageUrl: "")
        let session = CommentThread(kind: .session, contentID: 1, title: "Body Scan", imageUrl: "")

        #expect(journal == nil)
        #expect(session != nil)
        #expect(CommentThread(Fixtures.recipe(2)).kind == .recipe)
        #expect(CommentThread(MediaItem(id: 3, title: "Prompt", lead: "", imageUrl: "", mediaKind: .audio,
                                        storagePath: "", durationSeconds: 900, contentKind: .journal)) == nil)
    }

    @Test(arguments: [
        ("comment_link", CommentRefusal.link),
        ("comment_objectionable", .language),
        ("comment_rate_limit", .tooMany),
    ])
    func eachRefusalIsToldApart(_ message: String, _ refusal: CommentRefusal) {
        let error: any Error = PostgrestError(code: "P0001", message: message)

        #expect(error.commentRefusal == refusal)
    }

    @Test func otherFailuresAreNotRefusals() {
        #expect((PostgrestError(code: "42501", message: "new row violates row-level security policy") as any Error).commentRefusal == nil)
        #expect((URLError(.notConnectedToInternet) as any Error).commentRefusal == nil)
    }

    @Test func aReportOfACommentNamesItAndOffersTheCommentsReasons() throws {
        let fake = FakeComments()
        let theo = fake.member("Theo R.")
        let comment = fake.comment(by: theo)
        let target = ReportTarget(member: theo, comment: comment)
        let report = try #require(MemberReport(reportedID: theo.id, playID: nil, commentID: comment.id,
                                               reason: .offensive, details: ""))

        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])

        #expect(target.reasons == ReportReason.aboutAComment)
        #expect(ReportTarget(member: theo).reasons == ReportReason.aboutAMember)
        #expect(target.id == comment.id)
        #expect(json["comment_id"] as? String == comment.id.uuidString)
        #expect(json["reason"] as? String == "offensive")
        #expect(json["play_id"] == nil)
    }
}

// MARK: - The conversation

@MainActor
@Suite("Practice comments")
struct PracticeCommentsTests {

    // MARK: Reading

    @Test func aReadShowsTheCommentsNewestFirst() async {
        let fake = FakeComments()
        let theo = fake.member("Theo R."), nia = fake.member("Nia K.")
        fake.rows = [fake.comment(by: theo, "Newest"), fake.comment(by: nia, "Older")]
        let vm = fake.viewModel()

        await vm.load()

        #expect(vm.hasLoaded)
        #expect(vm.comments.map(\.body) == ["Newest", "Older"])
        #expect(vm.loadFailure == nil)
    }

    @Test func nothingCountsAsNobodyHavingSpokenUntilAReadAnswers() async {
        let fake = FakeComments()
        fake.fetchError = URLError(.notConnectedToInternet)
        let vm = fake.viewModel()

        #expect(!vm.hasLoaded)
        await vm.load()

        #expect(!vm.hasLoaded)
        #expect(vm.loadFailure == .offline)
    }

    @Test func aFailureAtOurEndIsToldApartFromOffline() async {
        let fake = FakeComments()
        fake.fetchError = URLError(.timedOut)
        let vm = fake.viewModel()

        await vm.load()

        #expect(vm.loadFailure == .failed)
    }

    @Test func aReloadThatFailsLeavesTheCommentsOnScreen() async {
        let fake = FakeComments()
        fake.rows = [fake.comment(by: fake.member("Theo R."))]
        let vm = fake.viewModel()
        await vm.load()
        fake.fetchError = URLError(.notConnectedToInternet)

        await vm.load(force: true)

        #expect(vm.comments.count == 1)
        #expect(vm.hasLoaded)
    }

    @Test func comingBackWithinAMinuteDoesNotReadAgain() async {
        let fake = FakeComments()
        let vm = fake.viewModel()
        await vm.load()

        fake.wait(30)
        await vm.load()
        #expect(fake.reads == 1)

        fake.wait(31)
        await vm.load()
        #expect(fake.reads == 2)
    }

    @Test func aFullThreadSaysThereIsMore() async {
        let fake = FakeComments()
        let theo = fake.member("Theo R.")
        fake.rows = (0..<PracticeCommentsViewModel.readLimit).map { _ in fake.comment(by: theo) }
        let vm = fake.viewModel()

        await vm.load()

        #expect(vm.countLabel == "\(PracticeCommentsViewModel.readLimit)+")
    }

    // MARK: Posting

    @Test func aPostLeadsTheListAndClearsTheDraft() async {
        let fake = FakeComments()
        fake.rows = [fake.comment(by: fake.member("Theo R."), "Earlier")]
        let vm = fake.viewModel()
        await vm.load()
        vm.draft = "  Shoulders down, finally.  "

        let posted = await vm.post()

        #expect(posted)
        #expect(fake.posted.map(\.body) == ["Shoulders down, finally."])
        #expect(vm.draft.isEmpty)
        #expect(vm.comments.first?.body == "Shoulders down, finally.")
        #expect(vm.comments.first?.isMine == true)
        #expect(vm.comments.count == 2)
        #expect(vm.postFailure == nil)
    }

    @Test func aPostThatFailsKeepsTheWordsAndSaysWhy() async {
        let fake = FakeComments()
        let vm = fake.viewModel()
        await vm.load()
        vm.draft = "Felt lighter."
        fake.writeError = URLError(.notConnectedToInternet)

        let posted = await vm.post()

        #expect(!posted)
        #expect(vm.draft == "Felt lighter.")
        #expect(vm.comments.isEmpty)
        #expect(vm.postFailure?.contains("offline") == true)
        #expect(!vm.isPosting)
    }

    @Test func aRetryOfTheSameWordsSendsTheSameID() async {
        let fake = FakeComments()
        let vm = fake.viewModel()
        vm.draft = "Felt lighter."
        fake.writeError = URLError(.timedOut)
        await vm.post()
        fake.writeError = nil

        await vm.post()
        vm.draft = "Something else."
        await vm.post()

        let ids = fake.attempts.map(\.id)
        #expect(ids.count == 3)
        // Had the timed-out attempt landed after all, the server takes its
        // retry as a duplicate key rather than a second comment.
        #expect(ids[0] == ids[1])
        #expect(ids[2] != ids[0])
        #expect(vm.comments.filter { $0.body == "Felt lighter." }.count == 1)
    }

    @Test func aRefusedPostSaysWhatToChange() async {
        let fake = FakeComments()
        let vm = fake.viewModel()
        vm.draft = "see www.example.com"
        fake.writeError = PostgrestError(code: "P0001", message: "comment_link")

        await vm.post()

        #expect(vm.postFailure == CommentRefusal.link.message)
        #expect(vm.draft == "see www.example.com")
    }

    @Test func nothingIsSentWithoutWords() async {
        let fake = FakeComments()
        let vm = fake.viewModel()
        vm.draft = "   "

        let posted = await vm.post()

        #expect(!posted)
        #expect(!vm.canPost)
        #expect(fake.posted.isEmpty)
    }

    @Test func aReadThatSetOffBeforeAPostCannotUndoIt() async {
        let fake = FakeComments()
        fake.rows = [fake.comment(by: fake.member("Theo R."), "Earlier")]
        let vm = fake.viewModel()
        await vm.load()
        fake.holdNextRead = true
        let staleRead = Task { await vm.load(force: true) }
        while !fake.isHoldingRead { await Task.yield() }

        vm.draft = "Mine"
        await vm.post()
        fake.release()
        await staleRead.value

        #expect(vm.comments.map(\.body) == ["Mine", "Earlier"])
    }

    // MARK: Deleting

    @Test func deletingYourCommentTakesItOffAtOnce() async {
        let fake = FakeComments()
        let mine = fake.myComment()
        fake.rows = [mine, fake.comment(by: fake.member("Theo R."))]
        let vm = fake.viewModel()
        await vm.load()

        await vm.delete(mine)

        #expect(fake.deleted == [mine.id])
        #expect(!vm.comments.contains { $0.id == mine.id })
        #expect(vm.comments.count == 1)
    }

    @Test func aRefusedDeletePutsItBackAndSaysSo() async {
        let fake = FakeComments()
        let mine = fake.myComment()
        fake.rows = [mine]
        let vm = fake.viewModel()
        await vm.load()
        fake.writeError = URLError(.notConnectedToInternet)

        await vm.delete(mine)

        #expect(vm.comments.map(\.id) == [mine.id])
        #expect(vm.actionError?.contains("offline") == true)
    }

    @Test func onlyYourOwnCommentCanBeDeleted() async {
        let fake = FakeComments()
        let theirs = fake.comment(by: fake.member("Theo R."))
        fake.rows = [theirs]
        let vm = fake.viewModel()
        await vm.load()

        await vm.delete(theirs)

        #expect(fake.deleted.isEmpty)
        #expect(vm.comments.count == 1)
    }

    // MARK: Report and Block

    @Test func blockingAnAuthorTakesEveryCommentOfTheirsOff() async {
        let fake = FakeComments()
        let theo = fake.member("Theo R."), nia = fake.member("Nia K.")
        fake.rows = [fake.comment(by: theo, "One"), fake.comment(by: nia), fake.comment(by: theo, "Two")]
        let vm = fake.viewModel()
        await vm.load()

        let held = await vm.block(theo)

        #expect(held)
        #expect(fake.blocked == [theo.id])
        #expect(vm.comments.map(\.author.id) == [nia.id])
    }

    @Test func aReadThatAnswersAfterTheBlockStillLeavesThemOut() async {
        let fake = FakeComments()
        let theo = fake.member("Theo R.")
        fake.rows = [fake.comment(by: theo)]
        let vm = fake.viewModel()
        await vm.load()
        await vm.block(theo)
        // The server's answer from before the block landed.
        fake.wait(61)

        await vm.load()

        #expect(vm.comments.isEmpty)
    }

    @Test func aRefusedBlockPutsTheCommentsBackAndSaysSo() async {
        let fake = FakeComments()
        let theo = fake.member("Theo R.")
        fake.rows = [fake.comment(by: theo)]
        let vm = fake.viewModel()
        await vm.load()
        fake.writeError = URLError(.notConnectedToInternet)

        let held = await vm.block(theo)

        #expect(!held)
        #expect(vm.comments.count == 1)
        #expect(vm.hiddenMembers.isEmpty)
        #expect(vm.actionError?.contains("Theo R.") == true)
    }

    @Test func noOneCanBlockThemselves() async {
        let fake = FakeComments()
        let mine = fake.myComment()
        fake.rows = [mine]
        let vm = fake.viewModel()
        await vm.load()

        let held = await vm.block(mine.author)

        #expect(!held)
        #expect(fake.blocked.isEmpty)
        #expect(vm.comments.count == 1)
    }

    @Test func aReportGoesToTheTeamAndAFailureReachesTheSheet() async throws {
        let fake = FakeComments()
        let theo = fake.member("Theo R.")
        let vm = fake.viewModel()
        let report = try #require(MemberReport(reportedID: theo.id, playID: nil, commentID: UUID(),
                                               reason: .harassment, details: ""))

        try await vm.report(report)
        fake.writeError = URLError(.notConnectedToInternet)
        await #expect(throws: URLError.self) { try await vm.report(report) }

        #expect(fake.reports == [report])
    }
}
