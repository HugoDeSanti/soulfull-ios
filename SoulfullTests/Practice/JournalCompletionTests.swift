//
//  JournalCompletionTests.swift
//  SoulfullTests
//
//  A visit to a journal prompt counts as practice done only if something was
//  written in it. "The reflection isn't empty" was true of every return to a
//  prompt written in before, so reading last week's entry for five seconds
//  kept the streak and finished a digital-retreat day.
//

import Testing
@testable import SoulfullGatherings

@Suite("Journal completion")
struct JournalCompletionTests {

    @Test(arguments: [
        // (written now, found on opening, counts)
        ("Today I noticed…", "", true),
        ("Last week's words", "Last week's words", false),
        ("Last week's words, and today's", "Last week's words", true),
        ("", "Last week's words", false),
        ("", "", false),
    ])
    func aVisitCountsOnlyIfSomethingWasWrittenInIt(entry: String, found: String, counts: Bool) {
        #expect(JournalCompletion.isDone(entry: entry, foundEntry: found) == counts)
    }
}
