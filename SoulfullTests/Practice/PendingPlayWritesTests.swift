//
//  PendingPlayWritesTests.swift
//  SoulfullTests
//
//  The practice writes that wait on the phone when the server can't be
//  reached. Each play keeps one write, folded the way the server folds a play
//  (most seconds, a finish that latches), and none waits longer than a day,
//  because the server would date it on arrival. Sending and retrying them is
//  PracticeProgressStoreTests.
//

import Foundation
import Testing
@preconcurrency import Supabase
@testable import SoulfullGatherings

@Suite("Pending play writes")
struct PendingPlayWritesTests {

    let member = UUID()
    let failedAt = Calendar.gregorian(in: "Europe/Madrid").at(2026, 9, 16, 12)
    let prompt = PracticePlay(kind: .journal, contentID: 3, title: "What is your body asking for?",
                              durationSeconds: 900)

    func write(_ play: PracticePlay, seconds: Int, completed: Bool = false,
               owner: UUID? = nil, since: Date? = nil) -> PendingPlayWrites.Write {
        PendingPlayWrites.Write(play, owner: owner ?? member, secondsPlayed: seconds,
                                positionSeconds: seconds, completed: completed,
                                since: since ?? failedAt)
    }

    @Test func aWaitingFinishRidesOnTheNextHeartbeat() {
        var queue = PendingPlayWrites()
        queue.hold(write(prompt, seconds: 120, completed: true))

        let next = queue.merged(write(prompt, seconds: 150, completed: false,
                                      since: failedAt.addingTimeInterval(30)))

        #expect(next.completed)
        #expect(next.secondsPlayed == 150)
        #expect(next.since == failedAt)
    }

    @Test func secondsNeverGoBackwards() {
        var queue = PendingPlayWrites()
        queue.hold(write(prompt, seconds: 300))

        #expect(queue.merged(write(prompt, seconds: 200)).secondsPlayed == 300)
    }

    @Test func aWriteThatLandedLeavesTheQueue() {
        var queue = PendingPlayWrites()
        let waiting = write(prompt, seconds: 120, completed: true)
        queue.hold(waiting)

        queue.settle(waiting)

        #expect(queue.isEmpty)
    }

    /// A later failure folded more in while this one was on its way.
    @Test func aWriteThatCarriedLessThanWhatWaitsLeavesItWaiting() {
        var queue = PendingPlayWrites()
        queue.hold(write(prompt, seconds: 120, completed: true))

        queue.settle(write(prompt, seconds: 120, completed: false))

        #expect(!queue.isEmpty)
    }

    @Test func aWriteWaitsADayAndNoLonger() {
        var queue = PendingPlayWrites()
        queue.hold(write(prompt, seconds: 120))

        let withinTheDay = queue.due(for: member, now: failedAt.addingTimeInterval(23 * 3600))
        let afterIt = queue.due(for: member, now: failedAt.addingTimeInterval(25 * 3600))

        #expect(withinTheDay.count == 1)
        #expect(afterIt.isEmpty)
        #expect(queue.isEmpty)
    }

    @Test func onlyTheMembersOwnWritesAreDue() {
        var queue = PendingPlayWrites()
        queue.hold(write(prompt, seconds: 120, owner: UUID()))

        #expect(queue.due(for: member, now: failedAt).isEmpty)
    }

    @Test func dueWritesComeOldestFirst() {
        var queue = PendingPlayWrites()
        let recipe = PracticePlay(kind: .recipe, contentID: 2, title: "Golden Lentil Soup")
        queue.hold(write(recipe, seconds: 60, since: failedAt.addingTimeInterval(600)))
        queue.hold(write(prompt, seconds: 60))

        #expect(queue.due(for: member, now: failedAt.addingTimeInterval(900)).map(\.eventID)
                == [prompt.eventID, recipe.eventID])
    }

    @Test func theQueueIsBoundedByDroppingTheOldest() {
        var queue = PendingPlayWrites()
        let first = PracticePlay(kind: .recipe, contentID: 1, title: "Oldest")
        queue.hold(write(first, seconds: 60))

        for offset in 1...PendingPlayWrites.capacity {
            let play = PracticePlay(kind: .recipe, contentID: 1, title: "Later")
            queue.hold(write(play, seconds: 60, since: failedAt.addingTimeInterval(Double(offset))))
        }

        #expect(queue.writes.count == PendingPlayWrites.capacity)
        #expect(queue.writes[first.eventID] == nil)
    }

    @Test func aWriteSurvivesBeingStored() throws {
        var queue = PendingPlayWrites()
        queue.hold(write(prompt, seconds: 120, completed: true))

        let stored = try JSONDecoder().decode(PendingPlayWrites.self,
                                              from: JSONEncoder().encode(queue))

        #expect(stored == queue)
        #expect(stored.writes[prompt.eventID]?.play == prompt)
    }

    // MARK: - Which failures wait

    @Test(arguments: [
        (URLError(.notConnectedToInternet) as any Error, true),
        (URLError(.timedOut) as any Error, true),
        (PostgrestError(code: "PGRST301", message: "JWT expired") as any Error, true),
        (PostgrestError(code: "PGRST000", message: "Could not connect to the database") as any Error, true),
        (PostgrestError(code: "23503", message: "practice_plays: journal 99 is not a practice") as any Error, false),
        (PostgrestError(code: "42501", message: "new row violates row-level security policy") as any Error, false),
    ])
    func aFailureIsRetriedUnlessTheDatabaseRefusedIt(_ error: any Error, retried: Bool) {
        #expect(PendingPlayWrites.isWorthRetrying(error) == retried)
    }
}
