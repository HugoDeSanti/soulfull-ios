//
//  RetreatBrochureTests.swift
//  SoulfullUITests
//
//  Guards the contract that makes adding a retreat a data change: a brochure
//  stored as jsonb in `retreats.experience` is fetched, decoded and rendered.
//
//  Worth a UI test rather than a unit test because the failure mode is silent.
//  `RetreatRow.decodedExperience` deliberately fails soft — a malformed
//  document logs and returns nil — so a bad decode doesn't crash or error, it
//  quietly downgrades the screen to the concise layout. Nothing but looking at
//  the rendered screen tells you the brochure stopped arriving.
//

import XCTest

final class RetreatBrochureTests: XCTestCase {

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMallorcaBrochureComesFromTheDatabase() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", "home"]
        app.launch()

        // Via the retreats stack rather than Home's shelf: the shelf scrolls
        // horizontally and Mallorca is its third card, so it exists but has no
        // valid activation point — even `isHittable` throws on it. The stack is
        // a vertical list of every retreat.
        // "All gatherings", not "ALL": Home has two of these now (gatherings and
        // programs) and they were indistinguishable to this query — and to
        // VoiceOver — until `SectionLabel` gained an accessibility label.
        let all = app.buttons["All gatherings"]
        XCTAssertTrue(all.waitForExistence(timeout: 30), "Home never finished loading")
        shot(app, "01-home")
        all.tap()

        // Each name in the stack is a button labelled "<name>, <country>". The
        // first tap on a name that isn't centred brings it into focus; the
        // card under the stack then opens whichever retreat is focused.
        let name = app.buttons["Mallorca, Spain"]
        XCTAssertTrue(name.waitForExistence(timeout: 20), "Mallorca never appeared in the stack")
        shot(app, "02-retreats-stack")
        name.tap()

        // The card's label names the focused retreat ("Explore Mallorca. Spain,
        // July 21–26, 2027"), so this only matches once Mallorca is centred.
        let open = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Explore Mallorca")
        ).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "The stack's card never focused Mallorca")
        open.tap()

        // "Who this is for" exists only in the brochure layout — `basicStory`
        // renders "The experience" / "The days" instead. Finding it proves the
        // jsonb document was fetched and decoded, not that a fallback rendered.
        //
        // `matching`, not `containing`: the latter matches elements that have a
        // matching *descendant*, which a leaf `Text` never does.
        let whoFor = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "who this is for")
        ).firstMatch
        XCTAssertTrue(whoFor.waitForExistence(timeout: 20),
                      "Brochure never rendered — the experience document didn't decode")
        shot(app, "02-brochure-top")

        app.swipeUp(velocity: .slow)
        app.swipeUp(velocity: .slow)
        shot(app, "03-brochure-elements")
    }
}
