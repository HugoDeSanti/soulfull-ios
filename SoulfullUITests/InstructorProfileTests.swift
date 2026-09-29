//
//  InstructorProfileTests.swift
//  SoulfullUITests
//
//  A guide's profile, reached the two ways the app offers: the Guides shelf on
//  the Practice tab, and a digital retreat's "with …" credit. The numbers and
//  the "Followed by" line read right, Follow moves them both and can be taken
//  back, the library opens where it should, and a guest reaching for Follow is
//  asked to sign in rather than shown an error.
//
//  Everything runs against `-preview-instructors` (InstructorDirectory's
//  fixture): no guide exists in the live database until the team writes one,
//  and the follow count must be deterministic to be asserted. Alma Guerra has
//  212 followers, follows 12 guides, three faces, a bio and a library of one
//  digital retreat and three sessions; Mara Solé has 75,712 followers and is
//  already followed; Rodrigo Peán has nothing at all.
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

    /// Opens a guide from the Practice tab's shelf, by name.
    private func openGuide(_ app: XCUIApplication, _ name: String) {
        let card = all(app, "guide-card").matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "No '\(name)' on the Guides shelf")
        card.tap()
        let title = element(app, "instructor-name")
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The profile never opened")
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

    func testTheGuidesShelfOpensAProfileWithItsNumbersBioAndLibrary() {
        let app = launch(tab: "practice", ["-preview-programs"])

        XCTAssertTrue(element(app, "guide-card").waitForExistence(timeout: 15), "The Guides shelf never appeared")
        XCTAssertEqual(all(app, "guide-card").count, 3, "The fixture has three guides")
        shot(app, "01-practice-guides-shelf")

        openGuide(app, "Alma Guerra")
        let followers = element(app, "instructor-followers")
        XCTAssertTrue(waitForLabel(followers, "212 followers"), "got '\(followers.label)'")
        XCTAssertEqual(element(app, "instructor-following").label, "Following 12")
        XCTAssertEqual(element(app, "instructor-followed-by").label,
                       "Followed by Theo R., Nia K. and 210 others",
                       "Two names, then the rest counted")
        XCTAssertEqual(element(app, "instructor-follow").label, "Follow")
        XCTAssertTrue(element(app, "instructor-bio").exists, "Alma has a bio")
        shot(app, "02-profile-top")

        let program = element(app, "instructor-library-program")
        XCTAssertTrue(program.waitForExistence(timeout: 10), "The library never loaded")
        XCTAssertEqual(all(app, "instructor-library-program").count, 1, "One digital retreat")
        XCTAssertEqual(all(app, "instructor-library-session").count, 3, "Three sessions")
        app.swipeUp()
        shot(app, "03-profile-library")

        // A digital retreat in the library opens on its own tab.
        program.tap()
        XCTAssertTrue(element(app, "program-guide").waitForExistence(timeout: 15),
                      "The digital retreat should open on the Digital Retreats tab, credited to its guide")
        shot(app, "04-handed-to-digital-retreats")
    }

    func testFollowingMovesTheCountAndPutsYouFirst() {
        let app = launch(tab: "practice")
        openGuide(app, "Alma Guerra")

        let follow = element(app, "instructor-follow")
        let followers = element(app, "instructor-followers")
        let followedBy = element(app, "instructor-followed-by")
        XCTAssertTrue(waitForLabel(followers, "212 followers"))

        follow.tap()
        XCTAssertTrue(waitForLabel(follow, "Following"), "A tap follows, got '\(follow.label)'")
        XCTAssertTrue(waitForLabel(followers, "213 followers"), "…and the count moves with it, got '\(followers.label)'")
        XCTAssertTrue(waitForLabel(followedBy, "Followed by you, Theo R. and 211 others"),
                      "You lead the line once you follow, got '\(followedBy.label)'")
        shot(app, "05-following")

        follow.tap()
        XCTAssertTrue(waitForLabel(follow, "Follow"), "A second tap unfollows")
        XCTAssertTrue(waitForLabel(followers, "212 followers"))
        XCTAssertTrue(waitForLabel(followedBy, "Followed by Theo R., Nia K. and 210 others"))
    }

    func testALargeCountIsCompactedAndAnEmptyProfileSaysSo() {
        let app = launch(tab: "practice")

        openGuide(app, "Mara Solé")
        let followers = element(app, "instructor-followers")
        XCTAssertTrue(waitForLabel(followers, "75,712 followers"), "got '\(followers.label)'")
        XCTAssertEqual(followers.value as? String, "75.7k", "Drawn compact, rounded down")
        XCTAssertTrue(waitForLabel(element(app, "instructor-follow"), "Following"), "Mara is already followed")
        XCTAssertEqual(element(app, "instructor-followed-by").label, "Followed by you, Theo R. and 75,710 others")
        shot(app, "06-large-count")

        element(app, "back-bar").tap()
        openGuide(app, "Rodrigo Peán")
        XCTAssertTrue(waitForLabel(element(app, "instructor-followers"), "0 followers"))
        XCTAssertEqual(element(app, "instructor-following").label, "Following 0")
        XCTAssertFalse(element(app, "instructor-followed-by").exists, "Nobody to name, so no line")
        XCTAssertFalse(element(app, "instructor-bio").exists, "No bio, so no About")
        XCTAssertTrue(element(app, "instructor-library-empty").waitForExistence(timeout: 10),
                      "An empty library says so rather than showing nothing")
        shot(app, "07-empty-profile")
    }

    func testADigitalRetreatsCreditOpensItsGuide() {
        let app = launch(tab: "programs", ["-preview-programs"])

        let card = app.buttons.matching(identifier: "program-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "The fixture catalog never appeared")
        card.tap()

        let credit = element(app, "program-guide")
        XCTAssertTrue(credit.waitForExistence(timeout: 10),
                      "A retreat linked to a published guide should credit them as a link")
        XCTAssertEqual(credit.label, "with Alma Guerra")
        shot(app, "08-program-credit")
        credit.tap()

        let title = element(app, "instructor-name")
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The credit never opened the profile")
        XCTAssertEqual(title.label, "Alma Guerra")
        let back = all(app, "back-bar").matching(NSPredicate(format: "label CONTAINS %@", "Finding Ground")).firstMatch
        XCTAssertTrue(back.exists, "Back names the retreat it came from")
        shot(app, "09-profile-from-credit")
    }

    /// Reading a profile is browsing; following is personal.
    func testAGuestReachingForFollowIsAskedToSignIn() {
        let app = launch(tab: "practice", ["-preview-guest"])
        openGuide(app, "Alma Guerra")

        let follow = element(app, "instructor-follow")
        XCTAssertTrue(follow.waitForExistence(timeout: 10))
        follow.tap()

        let close = app.buttons["account-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10),
                      "Following as a guest must raise the account sheet — the server refuses a guest anyway")
        shot(app, "10-account-sheet-on-follow")
        close.tap()

        XCTAssertTrue(follow.waitForExistence(timeout: 10))
        XCTAssertEqual(follow.label, "Follow", "Nothing was followed behind the sheet")
        XCTAssertEqual(element(app, "instructor-followers").label, "212 followers")
    }
}
