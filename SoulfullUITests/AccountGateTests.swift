//
//  AccountGateTests.swift
//  SoulfullUITests
//
//  Drives the just-in-time account gate, which is otherwise only verifiable by
//  hand: open a recipe as a guest, the account sheet appears, close it.
//

import XCTest

final class AccountGateTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testGuestOpeningRecipeSeesAccountSheetAndCanCloseIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", "practice"]
        app.launch()

        let recipes = app.buttons["Food Recipes"]
        XCTAssertTrue(recipes.waitForExistence(timeout: 20), "Practice landing never appeared")
        recipes.tap()

        let card = app.buttons.matching(identifier: "recipe-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Recipe list never appeared")
        shot(app, "01-recipe-list-as-guest")
        card.tap()

        // The gate should raise the account sheet rather than push the recipe.
        let close = app.buttons["account-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Account sheet never appeared")
        shot(app, "02-account-sheet-up")

        close.tap()

        // Regression guard: CircleIconButton once hit-tested only its glyph, so
        // this tap silently missed and the sheet stayed up (gotcha #5).
        let gone = close.waitForNonExistence(timeout: 8)
        shot(app, "03-after-close-tap")
        if !gone {
            let dump = app.debugDescription
            let attachment = XCTAttachment(string: dump)
            attachment.name = "hierarchy-after-close"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(gone, "Account sheet did not dismiss after tapping close")
    }
}
