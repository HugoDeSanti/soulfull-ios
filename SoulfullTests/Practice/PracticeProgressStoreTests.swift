//
//  PracticeProgressStoreTests.swift
//  SoulfullTests
//
//  A member's history as the app holds it between reads. A read that set off
//  for someone who has since signed out can't land on the next person, and the
//  local mirror of a heartbeat keeps "when it was last finished" the way the
//  server does (0029): it's the date a digital-retreat day asks for, and the
//  date of the last open is not it.
//

import Foundation
import Testing
@testable import SoulfullGatherings

@MainActor
@Suite("Practice progress store")
struct PracticeProgressStoreTests {

    @MainActor final class FakeHistory {
        var now = Calendar.gregorian(in: "Europe/Madrid").at(2026, 9, 16, 12)
        var me: UUID? = UUID()
        var progress: [PracticeProgress] = []
        /// Runs while a progress read is in flight: a sign-out, say.
        var duringRead: (() -> Void)?

        func store() -> PracticeProgressStore {
            PracticeProgressStore(backend: PracticeProgressBackend(
                currentUserID: { self.me },
                fetchProgress: { _ in
                    self.duringRead?()
                    return self.progress
                },
                fetchLedger: { _ in [] },
                recordPlay: { _, _, _, _, _ in },
                now: { self.now }
            ))
        }
    }

    let calendar = Calendar.gregorian(in: "Europe/Madrid")
    let boxBreathing = PracticePlay(kind: .session, contentID: 7, title: "Box Breathing",
                                    category: .breathwork, durationSeconds: 600)

    func finished(on date: Date) -> PracticeProgress {
        PracticeProgress(kind: .session, contentID: 7, title: "Box Breathing", creator: nil,
                         category: .breathwork, positionSeconds: 600, durationSeconds: 600,
                         totalSecondsPlayed: 600, completed: true, playCount: 1,
                         lastPlayedAt: date, lastCompletedAt: date)
    }

    // MARK: - Late reads

    @Test func aReadThatAnswersAfterTheMemberLeftIsDropped() async {
        let fake = FakeHistory()
        fake.progress = [finished(on: calendar.at(2026, 9, 1, 8))]
        let store = fake.store()
        fake.duringRead = {
            fake.me = nil
            store.clear()
        }

        await store.refresh()

        #expect(store.progress.isEmpty)
        #expect(store.loadedFor == nil)
    }

    @Test func aReadForTheSameMemberLands() async {
        let fake = FakeHistory()
        fake.progress = [finished(on: calendar.at(2026, 9, 1, 8))]
        let store = fake.store()

        await store.refresh()

        #expect(store.progress(for: boxBreathing) != nil)
        #expect(store.loadedFor == fake.me)
    }

    // MARK: - When it was finished

    @Test func openingAFinishedPracticeAgainKeepsWhenItWasFinished() async {
        let fake = FakeHistory()
        let finishedOn = calendar.at(2026, 8, 20, 19)
        fake.progress = [finished(on: finishedOn)]
        let store = fake.store()
        await store.refresh()

        await store.record(boxBreathing, owner: fake.me, secondsPlayed: 2, positionSeconds: 2, completed: false)

        let after = store.progress(for: boxBreathing)
        #expect(after?.lastPlayedAt == fake.now)
        #expect(after?.lastCompletedAt == finishedOn)
    }

    @Test func aPlayIsFinishedAtItsFirstFinishedHeartbeat() async {
        let fake = FakeHistory()
        let store = fake.store()
        await store.refresh()
        let finishedAt = fake.now

        await store.record(boxBreathing, owner: fake.me, secondsPlayed: 500, positionSeconds: 590, completed: true)
        fake.now = finishedAt.addingTimeInterval(20)
        await store.record(boxBreathing, owner: fake.me, secondsPlayed: 520, positionSeconds: 600, completed: true)

        #expect(store.progress(for: boxBreathing)?.lastCompletedAt == finishedAt)
    }

    @Test func finishingItAgainInANewSittingMovesTheFinish() async {
        let fake = FakeHistory()
        fake.progress = [finished(on: calendar.at(2026, 8, 20, 19))]
        let store = fake.store()
        await store.refresh()
        let again = PracticePlay(kind: .session, contentID: 7, title: "Box Breathing",
                                 category: .breathwork, durationSeconds: 600)

        await store.record(again, owner: fake.me, secondsPlayed: 590, positionSeconds: 600, completed: true)

        #expect(store.progress(for: again)?.lastCompletedAt == fake.now)
    }
}
