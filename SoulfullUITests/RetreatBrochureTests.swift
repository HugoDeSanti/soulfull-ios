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
        // Straight to the Gatherings tab, which is the retreats stack. Not via
        // Home's shelf: it scrolls horizontally and Mallorca is cards deep, so
        // it exists but has no valid activation point — even `isHittable`
        // throws on it.
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", "gatherings"]
        app.launch()

        // Through the catalog grid, not the stack's names. The stack shows the
        // focused name and the two after it, and Mallorca's place in it moves
        // whenever a retreat is added or dated earlier (third, then sixth from
        // 2026-09-30). XCUITest scrolls an off-screen name to the centre before
        // tapping it, and a tap on the centred name opens the retreat outright,
        // skipping the card this test goes through. A cover in the grid
        // refocuses the stack on its retreat wherever it sits.
        let toggle = app.buttons["Show all retreats"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "The stack never loaded")
        shot(app, "02-retreats-stack")
        toggle.tap()

        // A cover reads "<name>, <country>, <dates>"; the stack's name is just
        // "<name>, <country>", so the trailing comma picks the cover.
        let cover = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Mallorca, Spain, ")
        ).firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10), "Mallorca has no cover in the catalog")
        shot(app, "02-catalog")
        cover.tap()

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
