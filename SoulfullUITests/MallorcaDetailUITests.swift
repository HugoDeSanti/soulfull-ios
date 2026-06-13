//
//  MallorcaDetailUITests.swift
//  SoulfullUITests
//
//  Focused walk through the redesigned Mallorca retreat detail: opens the
//  detail and captures the cover plus each story section as it scrolls past,
//  so the editorial spread can be reviewed frame by frame.
//

import XCTest

final class MallorcaDetailUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMallorcaDetailSpread() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-onboarded"]
        app.launch()

        XCTAssertTrue(app.staticTexts["How do you feel?"].waitForExistence(timeout: 20))

        // Reveal the Upcoming gatherings carousel, then open Mallorca.
        app.swipeUp()
        sleep(1)
        let mallorca = mallorcaElement(app)
        XCTAssertTrue(mallorca.waitForExistence(timeout: 8), "Mallorca card should be present")
        mallorca.tap()
        sleep(2)
        snap(app, "md-cover")

        // Walk the story. Each swipe advances ~one viewport; we capture every
        // step so invitation → who → elements → member's word → guides →
        // stay & inclusions → closing all get a frame.
        for i in 1...7 {
            app.swipeUp(velocity: .slow)
            sleep(1)
            snap(app, String(format: "md-story-%02d", i))
        }
    }

    // MARK: - Helpers

    private func mallorcaElement(_ app: XCUIApplication) -> XCUIElement {
        if app.buttons["Mallorca"].exists { return app.buttons["Mallorca"] }
        let inButton = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Mallorca"))
        if inButton.firstMatch.exists { return inButton.firstMatch }
        return app.staticTexts.matching(identifier: "Mallorca").firstMatch
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
