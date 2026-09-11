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
        let all = app.buttons["ALL"]
        XCTAssertTrue(all.waitForExistence(timeout: 30), "Home never finished loading")
        shot(app, "01-home")
        all.tap()

        // The stack's names are Text, not Button — the tappable control is the
        // action pill in the bottom bar, which acts on whichever name is active.
        let name = app.staticTexts["Mallorca"]
        XCTAssertTrue(name.waitForExistence(timeout: 20), "Mallorca never appeared in the stack")
        shot(app, "02-retreats-stack")
        name.tap()

        // The bar is one combined accessibility element, so its label is the
        // whole summary line ("JULY 21-26, 2027 · SPAIN, …") rather than the
        // pill's own text.
        let open = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "SPAIN")
        ).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "No action pill in the stack bar")
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
