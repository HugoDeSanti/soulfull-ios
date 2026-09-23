//
//  PresenceTests.swift
//  SoulfullUITests
//
//  "75.7k present" on practices and digital retreats.
//
//  The first two run against the `-preview-presence` fixture, because the live
//  catalog has nothing with three people on it yet and the whole line is
//  absent below three — so without the fixture there is nothing to look at.
//  The third runs WITHOUT it and asserts the opposite: a row with no count is
//  a row with no line at all, never "0 present".
//

import XCTest

final class PresenceTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(tab: String, fixture: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", tab]
            + (fixture ? ["-preview-presence"] : [])
        app.launch()
        return app
    }

    /// Fresh each time: a shared NSPredicate can't be sent into XCTest's
    /// autoclosures under Swift 6.
    private static func present() -> NSPredicate {
        NSPredicate(format: "label CONTAINS ' present'")
    }

    private func openRecipes(_ app: XCUIApplication) -> XCUIElement {
        let recipes = app.buttons["Food Recipes"]
        XCTAssertTrue(recipes.waitForExistence(timeout: 20), "Practice landing never appeared")
        recipes.tap()
        let card = app.buttons.matching(identifier: "recipe-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Recipe list never appeared")
        return card
    }

    /// Every practice row carries the count, in the compact format, and the
    /// three faces are named for VoiceOver.
    func testPracticeRowsSayHowManyArePresent() {
        let app = launch(tab: "practice", fixture: true)
        let card = openRecipes(app)

        XCTAssertTrue(app.buttons.matching(identifier: "recipe-card").matching(Self.present()).firstMatch
                        .waitForExistence(timeout: 5),
                      "A recipe card doesn't mention who is present: \(card.label)")
        XCTAssertTrue(card.label.contains("including Alma G."),
                      "The faces aren't reaching VoiceOver: \(card.label)")
        shot(app, "01-recipes-present")

        // Journal prompts carry the count but never faces.
        app.buttons["back-bar"].firstMatch.tap()
        let journal = app.buttons["Journal Prompts"]
        XCTAssertTrue(journal.waitForExistence(timeout: 10))
        journal.tap()
        let prompt = app.buttons.matching(Self.present()).firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), "No journal prompt shows a count")
        XCTAssertFalse(prompt.label.contains("including"),
                       "A journal prompt named who is on it: \(prompt.label)")
        shot(app, "02-journal-count-only")
    }

    /// Digital retreats say how many are in flight, on the Programs tab.
    func testProgramsSayHowManyArePresent() {
        let app = launch(tab: "programs", fixture: true)
        let card = app.buttons.matching(identifier: "program-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 25), "Programs catalog never appeared")
        XCTAssertTrue(app.buttons.matching(identifier: "program-card").matching(Self.present()).firstMatch
                        .waitForExistence(timeout: 5),
                      "The program card doesn't say who is present: \(card.label)")
        shot(app, "03-programs-present")

        card.tap()
        XCTAssertTrue(app.otherElements["presence-badge"].waitForExistence(timeout: 10)
                      || app.staticTexts.matching(Self.present()).firstMatch.waitForExistence(timeout: 2),
                      "The program detail has no presence line")
        shot(app, "04-program-detail-present")
    }

    /// Against the live backend, nothing has three people yet — so no row
    /// may show a line. (If this starts failing because the app has grown,
    /// that's the good kind of failure: delete it.)
    func testNoLineBelowThreePeople() {
        let app = launch(tab: "practice", fixture: false)
        _ = openRecipes(app)
        // Give the RPC time to answer before asserting absence.
        Thread.sleep(forTimeInterval: 4)
        XCTAssertEqual(app.buttons.matching(Self.present()).count, 0,
                       "A practice shows a presence line with fewer than three people on it")
        shot(app, "05-recipes-live-no-line")
    }
}
