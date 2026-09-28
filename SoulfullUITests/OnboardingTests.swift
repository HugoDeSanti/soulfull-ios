//
//  OnboardingTests.swift
//  SoulfullUITests
//
//  The first launch: splash → the explainer slides → four questions → the
//  welcome → Home, greeting the person by the name they gave — and a relaunch
//  that goes straight to Home.
//
//  Every other UI test starts past this (`-uitest-onboarded`), and a Next that
//  never moves on here strands every new user before they have seen anything.
//  Which answers each question accepts is SoulfullTests/OnboardingFlowTests;
//  this only proves the real screens carry someone through.
//

import XCTest

@MainActor
final class OnboardingTests: XCTestCase {

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps the first choice on the current question, then Next, and waits
    /// for the counter to reach `nextStep`.
    private func answerWithFirstOption(_ app: XCUIApplication, then nextStep: String) {
        let option = app.buttons.matching(identifier: "onboarding-option").firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10), "No choices on this question")
        option.tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts[nextStep].waitForExistence(timeout: 10),
                      "Answering the question didn't move on to \(nextStep)")
    }

    func testANewUserIsCarriedFromTheSplashToHomeByName() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()

        let splash = app.staticTexts["TAP TO CONTINUE"]
        XCTAssertTrue(splash.waitForExistence(timeout: 30), "A first launch should open on the welcome splash")
        shot(app, "01-splash")
        splash.tap()

        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "The explainer slides never appeared")
        next.tap()
        let begin = app.buttons["Begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 10), "The last slide should offer Begin")
        begin.tap()

        let name = app.textFields["onboarding-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "Begin didn't open the first question")
        XCTAssertTrue(app.staticTexts["1/4"].exists)
        name.tap()
        name.typeText("Mara")
        shot(app, "02-name")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["2/4"].waitForExistence(timeout: 10), "A name didn't move on to 2/4")

        answerWithFirstOption(app, then: "3/4")
        answerWithFirstOption(app, then: "4/4")

        let option = app.buttons.matching(identifier: "onboarding-option").firstMatch
        option.tap()
        app.buttons["Next"].tap()
        let ready = app.buttons["I'm ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 10), "The last answer didn't reach the welcome")
        XCTAssertTrue(app.staticTexts["WELCOME, MARA"].exists, "The welcome should use the name given")
        shot(app, "03-welcome")
        ready.tap()

        XCTAssertTrue(app.staticTexts["Mara."].waitForExistence(timeout: 20),
                      "Onboarding should land on Home, greeting the new user by name")
        shot(app, "04-home")

        // Once is enough: a relaunch goes straight to Home.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Mara."].waitForExistence(timeout: 30),
                      "A returning user should land on Home")
        XCTAssertFalse(app.staticTexts["TAP TO CONTINUE"].exists, "A returning user was sent back through onboarding")
    }
}
