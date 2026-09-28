//
//  PresenceCountTests.swift
//  SoulfullTests
//
//  "75.7k present". Rounded DOWN, so the line never claims someone who isn't
//  there. (Whether a line shows at all — never below 3 people — is enforced
//  server-side and covered live by SoulfullUITests/PresenceTests.)
//

import Testing
@testable import SoulfullGatherings

@Suite("Presence count")
struct PresenceCountTests {

    @Test(arguments: [
        (3, "3"),
        (999, "999"),
        (1_000, "1k"),
        (1_050, "1k"),
        (1_999, "1.9k"),
        (75_749, "75.7k"),
        (999_999, "999.9k"),
        (1_000_000, "1M"),
        (1_190_000, "1.1M"),
    ])
    func countsAreCompactedAndRoundedDown(count: Int, compact: String) {
        #expect(Presence.compact(count) == compact)
    }

    @Test func theLabelSaysPresent() {
        #expect(Presence(count: 75_749, faces: []).label == "75.7k present")
    }
}
