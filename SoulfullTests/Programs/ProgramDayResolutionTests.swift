//
//  ProgramDayResolutionTests.swift
//  SoulfullTests
//
//  What a program day shows, and when it can close. A practice that is gone —
//  unpublished, never uploaded — is dropped, so a curriculum can't stall a
//  member forever. A practice that simply hasn't loaded yet is NOT: the day
//  can't be finished around it, because day completion is latched and the
//  practice is almost certainly there. Before the written libraries moved to
//  tables, "not loaded" and "gone" were the same answer.
//

import Testing
@testable import SoulfullGatherings

@Suite("Program day resolution")
struct ProgramDayResolutionTests {

    private let day = ProgramDay(day: 2, title: "Steadiness", activities: [
        ProgramActivity(kind: .journal, contentID: 1),
        ProgramActivity(kind: .exercise, contentID: 4),
        ProgramActivity(kind: .session, contentID: 7),
    ])

    private func found(_ activity: ProgramActivity) -> ActivityLookup {
        switch activity.kind {
        case .journal:  .found(.journal(Fixtures.journal(activity.contentID)))
        case .exercise: .found(.exercise(Fixtures.exercise(activity.contentID)))
        case .recipe:   .found(.recipe(Fixtures.recipe(activity.contentID)))
        case .session:  .found(.session(Fixtures.session(activity.contentID)))
        }
    }

    /// Everything found except `kind`, which answers `answer`.
    private func resolving(_ kind: PracticeContentKind, as answer: ActivityLookup) -> ProgramDayResolution {
        ProgramDayResolution(day) { $0.kind == kind ? answer : found($0) }
    }

    @Test func everythingFoundIsShownInCurriculumOrder() {
        let resolution = ProgramDayResolution(day, lookup: found)

        #expect(resolution.activities.map(\.id) == ["journal-1", "exercise-4", "session-7"])
        #expect(resolution.isSettled)
    }

    @Test func aPracticeThatIsGoneIsDroppedAndTheDayCanStillClose() {
        let resolution = resolving(.exercise, as: .missing)

        #expect(resolution.activities.map(\.id) == ["journal-1", "session-7"])
        #expect(resolution.isSettled)
        #expect(resolution.isFinished(isDone: { _ in true }))
    }

    @Test func aPracticeNotLoadedYetHoldsTheDayOpenEvenWhenTheRestIsDone() {
        let resolution = resolving(.journal, as: .pending)

        #expect(resolution.activities.map(\.id) == ["exercise-4", "session-7"])
        #expect(!resolution.isSettled)
        #expect(!resolution.isFinished(isDone: { _ in true }))
    }

    @Test func aDayWaitingOnEverythingIsNotFinished() {
        let resolution = ProgramDayResolution(day) { _ in .pending }

        #expect(resolution.activities.isEmpty)
        #expect(!resolution.isFinished(isDone: { _ in true }))
    }

    /// The lesser evil `ProgramStore.syncCompletion` documents: a day whose
    /// every practice is gone would otherwise trap the member on it forever.
    @Test func aDayWhoseEveryPracticeIsGoneCountsAsFinished() {
        let resolution = ProgramDayResolution(day) { _ in .missing }

        #expect(resolution.activities.isEmpty)
        #expect(resolution.isFinished(isDone: { _ in false }))
    }

    @Test func aSettledDayFinishesOnlyWhenEverythingInItIsDone() {
        let resolution = ProgramDayResolution(day, lookup: found)

        #expect(!resolution.isFinished(isDone: { $0.kind != .session }))
        #expect(resolution.isFinished(isDone: { _ in true }))
    }
}
