//
//  SoulfullTourUITests.swift
//  SoulfullUITests
//
//  Drives the full first-run journey and the main browsing flows, attaching
//  a named screenshot at every beat. Run with the SoulfullGatherings scheme;
//  export attachments from the .xcresult to review the tour frame by frame.
//

import XCTest

final class SoulfullTourUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstRunTour() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()

        // ── Welcome ────────────────────────────────────────────────────────
        XCTAssertTrue(app.staticTexts["TAP TO CONTINUE"].waitForExistence(timeout: 20),
                      "Splash should appear once auth settles")
        snap(app, "01-welcome-splash")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 6))
        snap(app, "02-welcome-slide1")

        app.buttons["Next"].tap()
        sleep(1)
        snap(app, "03-welcome-slide2")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.buttons["Begin"].waitForExistence(timeout: 6))
        snap(app, "04-welcome-slide3")
        app.buttons["Begin"].tap()

        // ── Onboarding ─────────────────────────────────────────────────────
        XCTAssertTrue(app.staticTexts["What should we call you?"].waitForExistence(timeout: 6))
        snap(app, "05-onboarding-name")

        let nameField = app.textFields.firstMatch
        if nameField.waitForExistence(timeout: 4) {
            nameField.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 3) {
                app.typeText("Mara")
                snap(app, "06-onboarding-name-filled")
                app.buttons["Next"].tap()
            } else {
                // Hardware-keyboard sims: fall back to skipping onboarding.
                app.buttons["skip"].tap()
            }
        }

        // Intention step (multi-select grid)
        if app.staticTexts["travel & retreat"].waitForExistence(timeout: 6) {
            app.staticTexts["travel & retreat"].tap()
            app.staticTexts["rest & recover"].tap()
            snap(app, "07-onboarding-intentions")
            app.buttons["Next"].tap()

            // Body state
            XCTAssertTrue(app.staticTexts["soft & open"].waitForExistence(timeout: 6))
            app.staticTexts["soft & open"].tap()
            snap(app, "08-onboarding-state")
            app.buttons["Next"].tap()

            // Frequency
            XCTAssertTrue(app.staticTexts["every day"].waitForExistence(timeout: 6))
            app.staticTexts["every day"].tap()
            snap(app, "09-onboarding-frequency")
            app.buttons["Next"].tap()

            // Finish
            XCTAssertTrue(app.buttons["I'm ready"].waitForExistence(timeout: 6))
            snap(app, "10-onboarding-finish")
            app.buttons["I'm ready"].tap()
        }

        // ── Home ───────────────────────────────────────────────────────────
        XCTAssertTrue(app.staticTexts["How do you feel?"].waitForExistence(timeout: 10))
        snap(app, "11-home-top")

        tapAny(app, "Grateful")
        snap(app, "12-home-mood-selected")

        app.swipeUp()
        sleep(1)
        snap(app, "13-home-scrolled")

        // ── Retreat detail via zoom hero ───────────────────────────────────
        if element(app, containing: "Mallorca").waitForExistence(timeout: 6) {
            element(app, containing: "Mallorca").tap()
            sleep(1)
            snap(app, "14-retreat-detail-cover")

            app.swipeUp()
            sleep(1)
            snap(app, "15-retreat-detail-story")

            app.buttons["Back"].firstMatch.tap()
            sleep(1)
        }

        // ── Retreats stack + catalog ───────────────────────────────────────
        app.buttons["ALL"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["SOULFULL"].waitForExistence(timeout: 8))
        sleep(1)
        snap(app, "16-retreats-stack")

        // Scroll the typographic stack
        app.swipeUp(velocity: .slow)
        sleep(1)
        snap(app, "17-retreats-stack-scrolled")

        // Pinch out → catalog contact sheet
        app.pinch(withScale: 0.5, velocity: -0.8)
        XCTAssertTrue(app.staticTexts["THE CATALOG"].waitForExistence(timeout: 6),
                      "Pinching out should open the catalog")
        sleep(1)
        snap(app, "18-retreats-catalog")

        // Tap a cover → back to the stack focused on it
        if element(app, containing: "Kyoto").waitForExistence(timeout: 4) {
            element(app, containing: "Kyoto").tap()
            XCTAssertTrue(app.staticTexts["SOULFULL"].waitForExistence(timeout: 6))
            sleep(1)
            snap(app, "19-retreats-stack-refocused")
        }

        app.buttons["Close"].tap()
        sleep(1)

        // ── Other tabs ─────────────────────────────────────────────────────
        app.buttons["Practice"].tap()
        sleep(1)
        snap(app, "20-practice")

        app.buttons["Circle"].tap()
        sleep(1)
        snap(app, "21-circle")

        app.buttons["You"].tap()
        sleep(1)
        snap(app, "22-you")
    }

    // MARK: - Helpers

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Buttons fold their inner Text into the button label, so the same
    /// visible string may surface as a button, a static text, or a label
    /// substring depending on the container. Try all three.
    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        if app.buttons[text].exists { return app.buttons[text] }
        let inButton = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", text))
        if inButton.firstMatch.exists { return inButton.firstMatch }
        return app.staticTexts.matching(identifier: text).firstMatch
    }

    private func tapAny(_ app: XCUIApplication, _ text: String) {
        let el = element(app, containing: text)
        if el.waitForExistence(timeout: 4) { el.tap() }
    }
}
