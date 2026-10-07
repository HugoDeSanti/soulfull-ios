//
//  PasswordResetTests.swift
//  SoulfullUITests
//
//  "Forgot password?" on the sign-in sheet, against live Supabase: the address
//  carries over, a code is asked for, and a wrong code is turned away without
//  leaving the panel. Before this a member who forgot their password was
//  locked out for good.
//
//  The address has no account, so GoTrue answers the request exactly as it
//  would for a real one and sends nothing. Which code and password the panel
//  accepts, and that a code is spent once, is SoulfullTests/PasswordResetFlowTests.
//

import XCTest

@MainActor
final class PasswordResetTests: XCTestCase {

    /// No account uses this address. Don't create one: the test would then
    /// email it a real code on every run.
    private let address = "uitest-no-account@soulfullgatherings.com"

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Welcome → "I already have an account" → the sign-in sheet.
    private func openSignIn(_ app: XCUIApplication) {
        let splash = app.staticTexts["TAP TO CONTINUE"]
        XCTAssertTrue(splash.waitForExistence(timeout: 30), "A first launch should open on the welcome splash")
        splash.tap()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "The explainer slides never appeared")
        next.tap()
        let haveAccount = app.buttons["I already have an account"]
        XCTAssertTrue(haveAccount.waitForExistence(timeout: 10), "The last slide should offer sign-in")
        haveAccount.tap()
    }

    func testForgotPasswordSendsACodeAndTurnsAWrongOneAway() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
        openSignIn(app)

        let email = app.textFields["account-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10), "The sign-in sheet never appeared")
        email.tap()
        email.typeText(address)
        let forgot = app.buttons["forgot-password"]
        XCTAssertTrue(forgot.exists, "Sign-in should offer \"Forgot password?\"")
        shot(app, "01-sign-in-with-forgot-password")
        forgot.tap()

        // The address they'd typed comes with them.
        let resetEmail = app.textFields["reset-email"]
        XCTAssertTrue(resetEmail.waitForExistence(timeout: 10), "\"Forgot password?\" didn't open the reset panel")
        XCTAssertEqual(resetEmail.value as? String, address)
        shot(app, "02-reset-request")
        app.buttons["reset-send"].tap()

        let code = app.textFields["reset-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 30), "Sending the code never moved on to the code panel")
        XCTAssertTrue(app.staticTexts["Check your email"].exists)
        code.tap()
        code.typeText("000000")
        // `.newPassword` makes iOS offer a strong password, and while that
        // sheet is up it swallows typing. Take the offer, as most people do.
        let newPassword = app.secureTextFields["reset-new-password"]
        newPassword.tap()
        let suggested = app.buttons["GenerateStrongPasswordButton"]
        if suggested.waitForExistence(timeout: 4) {
            shot(app, "03a-strong-password-offer")
            suggested.tap()
        } else {
            newPassword.typeText("a-new-password")
        }
        shot(app, "03-code-and-new-password")
        app.buttons["reset-submit"].tap()

        let refused = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "code didn't work")).firstMatch
        XCTAssertTrue(refused.waitForExistence(timeout: 30), "A wrong code should be turned away with a reason")
        XCTAssertTrue(code.exists, "A wrong code should leave the code field to fix")
        shot(app, "04-wrong-code")

        app.buttons["reset-back"].tap()
        XCTAssertTrue(email.waitForExistence(timeout: 10), "\"Back to sign in\" should return to the form")
        XCTAssertEqual(email.value as? String, address, "The address should carry back to the form")
        XCTAssertTrue(forgot.exists)
        shot(app, "05-back-on-sign-in")
    }
}
