//
//  MediaTimeMeterTests.swift
//  SoulfullTests
//
//  What a creator is paid for: media time actually played. Not wall-clock,
//  not the scrubber position — a seek banks nothing and a pause accrues
//  nothing. And what finishing a session takes: reaching its end having
//  heard most of it, never a scrub to the last seconds. The player observes
//  once a second.
//

import Testing
@testable import SoulfullGatherings

@Suite("Media time meter")
struct MediaTimeMeterTests {

    func meter(duration: Int? = 600, earlier: PracticeProgress? = nil,
               observing times: [Double]) -> MediaTimeMeter {
        var meter = MediaTimeMeter(durationSeconds: duration, earlier: earlier)
        for time in times { meter.observe(time) }
        return meter
    }

    /// One reading a second from `start` through `end`, as the player makes them.
    func playing(_ start: Int, through end: Int) -> [Double] {
        (start...end).map(Double.init)
    }

    func earlierSitting(listened seconds: Int, finished: Bool = false) -> PracticeProgress {
        PracticeProgress(kind: .session, contentID: 1, title: "Box Breathing", creator: nil,
                         category: .breathwork, positionSeconds: seconds, durationSeconds: 600,
                         totalSecondsPlayed: seconds, completed: finished, playCount: 1,
                         lastPlayedAt: .distantPast)
    }

    @Test func steadyPlaybackAccruesMediaTime() {
        let result = meter(observing: (0...30).map(Double.init))

        #expect(result.playedSeconds == 30)
        #expect(result.positionSeconds == 30)
    }

    @Test func seekingForwardBanksNothing() {
        let result = meter(observing: [0, 1, 2, 250, 251])

        #expect(result.playedSeconds == 3)
        #expect(result.positionSeconds == 251)
    }

    @Test func seekingBackBanksNothingButReplayingCounts() {
        let result = meter(observing: (0...10).map(Double.init) + [3, 4])

        #expect(result.playedSeconds == 11)
    }

    @Test func aPausedPlayerAccruesNothing() {
        let result = meter(observing: [5, 6, 6, 6, 6])

        #expect(result.playedSeconds == 1)
    }

    @Test func unreadableTimesAreIgnored() {
        let result = meter(observing: [0, 1, .nan, .infinity, 2])

        #expect(result.playedSeconds == 2)
        #expect(result.positionSeconds == 2)
    }

    // MARK: - Finishing

    /// Some encoders leave the last fraction of a second unreachable, so the
    /// end is within two seconds of it.
    @Test(arguments: [(597, false), (598, true)])
    func listeningThroughFinishesWithinTwoSecondsOfTheEnd(through end: Int, finished: Bool) {
        #expect(meter(observing: playing(0, through: end)).didComplete == finished)
    }

    /// Regression: reaching the end used to be enough, so a scrub to the last
    /// seconds finished a session — a class, a streak day, a program activity.
    @Test func scrubbingToTheEndDoesNotFinishASession() {
        var result = meter(observing: [0, 1, 2, 599, 600])

        result.markReachedEnd()

        #expect(!result.didComplete)
        #expect(result.playedSeconds == 3)
    }

    @Test func scrubbingNearTheEndAndListeningOnDoesNotFinishIt() {
        var result = meter(observing: playing(0, through: 5) + playing(570, through: 600))

        result.markReachedEnd()

        #expect(!result.didComplete)
    }

    /// Four fifths is the bar: an intro or a closing silence can be skipped.
    @Test func skippingAShortStretchStillFinishes() {
        let result = meter(observing: playing(0, through: 60) + playing(150, through: 600))

        #expect(result.didComplete)
    }

    @Test func aSessionHeardAcrossTwoSittingsFinishes() {
        let result = meter(earlier: earlierSitting(listened: 360), observing: playing(360, through: 600))

        #expect(result.didComplete)
    }

    /// A resume point is only a position — what counts is what was heard
    /// before it.
    @Test func resumingNearTheEndWithLittleHeardDoesNotFinishIt() {
        let result = meter(earlier: earlierSitting(listened: 5), observing: playing(560, through: 600))

        #expect(!result.didComplete)
    }

    @Test func aFinishedSessionMustBeHeardAgainToCountAgain() {
        var result = meter(earlier: earlierSitting(listened: 600, finished: true),
                           observing: [0, 1, 599, 600])

        result.markReachedEnd()

        #expect(!result.didComplete)
    }

    @Test func fallingShortCanBeMadeGoodByListening() {
        var result = meter(observing: [0, 599, 600])
        result.markReachedEnd()
        #expect(!result.didComplete)

        for time in playing(0, through: 600) { result.observe(time) }

        #expect(result.didComplete)
    }

    /// With no known length, where the end turned out to be is the length.
    @Test func withoutALengthTheEndOfTheItemFinishesItOnlyIfItWasHeard() {
        var heard = meter(duration: nil, observing: playing(0, through: 100))
        var scrubbed = meter(duration: nil, observing: [0, 1, 5_000])

        heard.markReachedEnd()
        scrubbed.markReachedEnd()

        #expect(heard.didComplete)
        #expect(!scrubbed.didComplete)
    }
}
