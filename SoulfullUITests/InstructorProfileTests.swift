//
//  InstructorProfileTests.swift
//  SoulfullUITests
//
//  Guides are met on the pages of what they made, never on the Practice
//  landing. A movement sequence, a recipe, a prompt and a digital retreat each
//  carry a "Your guide" card when their content names a guide — and nothing
//  when it doesn't. The card opens the guide's profile, whose numbers and
//  "Followed by" line read right, whose Follow moves them both and can be
//  taken back, and whose library opens where it should. A guest reaching for
//  Follow is asked to sign in rather than shown an error.
//
//  Everything runs against `-preview-instructors` (InstructorDirectory's
//  fixture), browsed as a member unless `-preview-guest` is passed: the live
//  guides are placeholders that will be replaced, and the counts must be
//  deterministic to be asserted. Alma Guerra has 212 followers, follows 12,
//  three faces, a bio, and a library of Finding Ground, three sessions, the
//  first movement sequence and the first recipe; Mara Solé has 75,712
//  followers, is already followed, and is credited with the gratitude prompt.
//

import XCTest

@MainActor
final class InstructorProfileTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(tab: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", tab, "-preview-instructors"] + extra
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func all(_ app: XCUIApplication, _ id: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: id)
    }

    /// Scrolls until `element`'s centre — where `tap()` lands — sits above the
    /// docked bar. `isHittable` alone isn't enough: a card under the bar still
    /// reports hittable, and the tap lands on a tab. XCUITest's own scroll to
    /// an off-screen card can stop with it there.
    private func scrollClearOfTheBar(_ element: XCUIElement, _ app: XCUIApplication) {
        let floor = app.windows.firstMatch.frame.maxY - 140
        var tries = 0
        while (!element.isHittable || element.frame.midY > floor) && tries < 8 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        XCTAssertTrue(element.isHittable && element.frame.midY <= floor,
                      "The card never scrolled clear of the tab bar")
    }

    /// From the Practice landing: a section card, then the row titled `title`.
    private func openPractice(_ app: XCUIApplication, section: String, title: String) {
        let card = app.buttons[section]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "No '\(section)' on the Practice landing")
        scrollClearOfTheBar(card, app)
        card.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "No '\(title)' in \(section)")
        row.tap()
    }

    /// The page's "Your guide" card, which must name `name`.
    private func guideCard(_ app: XCUIApplication, naming name: String) -> XCUIElement {
        let card = element(app, "guide-card")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "This page should name its guide")
        XCTAssertTrue(card.label.hasPrefix("Your guide, \(name)"), "got '\(card.label)'")
        return card
    }

    /// Opens a profile from a guide card and checks whose it is.
    private func openProfile(_ app: XCUIApplication, from card: XCUIElement, _ name: String) {
        card.tap()
        let title = element(app, "instructor-name")
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The guide card never opened the profile")
        XCTAssertEqual(title.label, name)
    }

    /// Waits for an element's label to settle on `expected`.
    private func waitForLabel(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.label != expected && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element.label == expected
    }

    /// Opens a digital retreat's page from the fixture catalog.
    private func openProgram(_ app: XCUIApplication) {
        let card = app.buttons.matching(identifier: "program-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "The fixture catalog never appeared")
        card.tap()
    }

    func testAPracticePageNamesItsGuideAndTheLandingNamesNone() {
        let app = launch(tab: "practice", ["-preview-programs"])

        XCTAssertTrue(app.buttons["Movement"].waitForExistence(timeout: 20))
        XCTAssertFalse(element(app, "guide-card").exists, "Guides are met on their practices, not on the landing")
        XCTAssertFalse(app.staticTexts["THE GUIDES"].exists)
        shot(app, "01-landing-without-guides")

        // A sequence nobody is credited with has no card at all.
        openPractice(app, section: "Movement", title: "Core Foundations")
        XCTAssertTrue(app.staticTexts["THE SEQUENCE"].waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "guide-card").exists, "No guide credited, so no card")
        element(app, "back-bar").tap()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Morning Mobility Flow")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let card = guideCard(app, naming: "Alma Guerra")
        shot(app, "02-movement-page-with-guide")

        openProfile(app, from: card, "Alma Guerra")
        XCTAssertTrue(all(app, "back-bar").matching(NSPredicate(format: "label CONTAINS %@", "Morning Mobility Flow")).firstMatch.exists,
                      "Back names the practice it came from")
        XCTAssertTrue(waitForLabel(element(app, "instructor-followers"), "212 followers"))
        XCTAssertEqual(element(app, "instructor-following").label, "Following 12")
        XCTAssertEqual(element(app, "instructor-followed-by").label, "Followed by Theo R., Nia K. and 210 others",
                       "Two names, then the rest counted")
        XCTAssertEqual(element(app, "instructor-follow").label, "Follow")
        XCTAssertTrue(element(app, "instructor-bio").exists)
        shot(app, "03-profile")

        let program = element(app, "instructor-library-program")
        XCTAssertTrue(program.waitForExistence(timeout: 10), "The library never loaded")
        XCTAssertEqual(all(app, "instructor-library-program").count, 1, "One digital retreat")
        XCTAssertEqual(all(app, "instructor-library-session").count, 3, "Three sessions")
        XCTAssertEqual(all(app, "instructor-library-practice").count, 2, "One movement sequence and one recipe")
        app.swipeUp()
        app.swipeUp()
        shot(app, "04-profile-library")

        // A digital retreat in the library opens on its own tab — whose page
        // names the same guide.
        program.tap()
        _ = guideCard(app, naming: "Alma Guerra")
        shot(app, "05-handed-to-digital-retreats")
    }

    func testFollowingMovesTheCountAndPutsYouFirst() {
        let app = launch(tab: "programs", ["-preview-programs"])
        openProgram(app)
        let card = guideCard(app, naming: "Alma Guerra")
        shot(app, "06-digital-retreat-with-guide")
        openProfile(app, from: card, "Alma Guerra")

        let follow = element(app, "instructor-follow")
        let followers = element(app, "instructor-followers")
        let followedBy = element(app, "instructor-followed-by")
        XCTAssertTrue(waitForLabel(followers, "212 followers"))
        XCTAssertTrue(all(app, "back-bar").matching(NSPredicate(format: "label CONTAINS %@", "Finding Ground")).firstMatch.exists,
                      "Back names the digital retreat it came from")

        follow.tap()
        XCTAssertTrue(waitForLabel(follow, "Following"), "A tap follows, got '\(follow.label)'")
        XCTAssertTrue(waitForLabel(followers, "213 followers"), "…and the count moves with it, got '\(followers.label)'")
        XCTAssertTrue(waitForLabel(followedBy, "Followed by you, Theo R. and 211 others"),
                      "You lead the line once you follow, got '\(followedBy.label)'")
        shot(app, "07-following")

        follow.tap()
        XCTAssertTrue(waitForLabel(follow, "Follow"), "A second tap unfollows")
        XCTAssertTrue(waitForLabel(followers, "212 followers"))
        XCTAssertTrue(waitForLabel(followedBy, "Followed by Theo R., Nia K. and 210 others"))
    }

    func testRecipesAndPromptsNameTheirGuides() {
        let recipeApp = launch(tab: "practice")
        openPractice(recipeApp, section: "Food Recipes", title: "Golden Turmeric Lentils")
        _ = guideCard(recipeApp, naming: "Alma Guerra")
        shot(recipeApp, "08-recipe-with-guide")
        recipeApp.terminate()

        let app = launch(tab: "practice")
        openPractice(app, section: "Journal Prompts", title: "Where did you feel ease this week?")
        let card = guideCard(app, naming: "Mara Solé")
        app.swipeUp()
        shot(app, "09-prompt-with-guide")
        openProfile(app, from: card, "Mara Solé")

        let followers = element(app, "instructor-followers")
        XCTAssertTrue(waitForLabel(followers, "75,712 followers"), "got '\(followers.label)'")
        XCTAssertEqual(followers.value as? String, "75.7k", "Drawn compact, rounded down")
        XCTAssertTrue(waitForLabel(element(app, "instructor-follow"), "Following"), "Mara is already followed")
        XCTAssertEqual(element(app, "instructor-followed-by").label, "Followed by you, Theo R. and 75,710 others")
        XCTAssertTrue(element(app, "instructor-library-practice").waitForExistence(timeout: 10))
        XCTAssertEqual(all(app, "instructor-library-practice").count, 1, "The prompt she is credited with")
        shot(app, "10-large-count")
    }

    /// Reading a profile is browsing; following is personal.
    func testAGuestReachingForFollowIsAskedToSignIn() {
        let app = launch(tab: "programs", ["-preview-programs", "-preview-guest"])
        openProgram(app)
        openProfile(app, from: guideCard(app, naming: "Alma Guerra"), "Alma Guerra")

        let follow = element(app, "instructor-follow")
        XCTAssertTrue(follow.waitForExistence(timeout: 10))
        follow.tap()

        let close = app.buttons["account-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10),
                      "Following as a guest must raise the account sheet — the server refuses a guest anyway")
        shot(app, "11-account-sheet-on-follow")
        close.tap()

        XCTAssertTrue(follow.waitForExistence(timeout: 10))
        XCTAssertEqual(follow.label, "Follow", "Nothing was followed behind the sheet")
        XCTAssertEqual(element(app, "instructor-followers").label, "212 followers")
    }
}
