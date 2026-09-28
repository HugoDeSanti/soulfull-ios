//
//  MediaTimeMeterTests.swift
//  SoulfullTests
//
//  What a creator is paid for: media time actually played. Not wall-clock,
//  not the scrubber position — a seek banks nothing and a pause accrues
//  nothing. The player observes once a second.
//

import Testing
@testable import SoulfullGatherings

@Suite("Media time meter")
struct MediaTimeMeterTests {

    func meter(duration: Int? = 600, observing times: [Double]) -> MediaTimeMeter {
        var meter = MediaTimeMeter(durationSeconds: duration)
        for time in times { meter.observe(time) }
        return meter
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

    /// Some encoders leave the last fraction of a second unreachable, so
    /// "finished" is within two seconds of the end.
    @Test(arguments: [(597.0, false), (598.0, true), (600.0, true)])
    func finishingIsWithinTwoSecondsOfTheEnd(time: Double, finished: Bool) {
        #expect(meter(duration: 600, observing: [time]).didComplete == finished)
    }

    @Test func withoutALengthOnlyTheEndOfTheItemFinishesIt() {
        var result = meter(duration: nil, observing: [0, 1, 5_000])
        #expect(!result.didComplete)

        result.markCompleted()

        #expect(result.didComplete)
    }
}
