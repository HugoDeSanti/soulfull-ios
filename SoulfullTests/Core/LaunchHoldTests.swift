//
//  LaunchHoldTests.swift
//  SoulfullTests
//
//  When the launch logo gives way. It used to wait for the session check
//  itself, which on a stalled connection sat out URLSession's 60-second
//  timeout. Now it leaves when the check settles or the grace passes,
//  whichever is first, and only once, while the check carries on behind it.
//
//  The grace and the check are gates the test opens, so nothing here sleeps.
//

import Testing
@testable import SoulfullGatherings

/// Suspends whoever waits until the test opens it.
@MainActor
private final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
private final class Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@Suite("Launch hold", .timeLimit(.minutes(1)))
@MainActor
struct LaunchHoldTests {

    @Test func aQuickSessionCheckLeavesTheLogoWithoutWaitingForTheGrace() async {
        let leaves = Counter()

        await LaunchHold.run(
            restore: {},
            grace: { try? await Task.sleep(for: .seconds(3600)) },
            leave: { leaves.increment() }
        )

        #expect(leaves.value == 1)
    }

    @Test func aStalledSessionCheckLeavesTheLogoWhenTheGracePasses() async {
        let check = Gate()
        let left = Gate()
        let leaves = Counter()
        let launch = Task {
            await LaunchHold.run(
                restore: { await check.wait() },
                grace: {},
                leave: { leaves.increment(); left.open() }
            )
        }

        await left.wait()

        #expect(leaves.value == 1)
        check.open()
        await launch.value
    }

    /// `run` returning is what the app's push sync waits for, so it has to
    /// mean the session is settled, not just that the logo is gone.
    @Test func runReturnsOnlyOnceTheStalledCheckSettles() async {
        let check = Gate()
        let left = Gate()
        let settled = Counter()
        let launch = Task {
            await LaunchHold.run(
                restore: { await check.wait(); settled.increment() },
                grace: {},
                leave: { left.open() }
            )
            return settled.value
        }
        await left.wait()

        check.open()
        let settledWhenItReturned = await launch.value

        #expect(settledWhenItReturned == 1)
    }

    @Test func aStalledCheckThatSettlesAfterTheGraceDoesNotLeaveTwice() async {
        let check = Gate()
        let left = Gate()
        let leaves = Counter()
        let launch = Task {
            await LaunchHold.run(
                restore: { await check.wait() },
                grace: {},
                leave: { leaves.increment(); left.open() }
            )
        }
        await left.wait()

        check.open()
        await launch.value

        #expect(leaves.value == 1)
    }

    @Test func aGraceThatPassesAfterTheCheckSettledDoesNotLeaveTwice() async {
        let graceEnds = Gate()
        let graceOver = Gate()
        let leaves = Counter()
        await LaunchHold.run(
            restore: {},
            grace: { await graceEnds.wait(); graceOver.open() },
            leave: { leaves.increment() }
        )

        graceEnds.open()
        await graceOver.wait()

        #expect(leaves.value == 1)
    }
}
