//
//  CommunityTests.swift
//  SoulfullUITests
//
//  The Community tab: the feed reads as sentences with a face beside each,
//  the All | Friends toggle actually narrows it, the Friends screen moves a
//  request from waiting to accepted, and a guest reaching for Friends is asked
//  to sign in — not shown an empty list or a bare error.
//
//  The populated screens run against the `-preview-community` fixture, which
//  holds four members (one of them "you"), six finished practices, two
//  friends, one request waiting on you and one you sent. The guest test runs
//  against the live backend, where the gate is the thing under test.
//

import XCTest

final class CommunityTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(fixture: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", "community"]
        if fixture { app.launchArguments.append("-preview-community") }
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "activity-row")
    }

    /// One line per finished practice, "Name practiced Title", your own as "You".
    func testFeedReadsAsSentencesAndFriendsNarrowsIt() {
        let app = launch(fixture: true)

        let first = rows(app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), "The feed never rendered")
        let labels = rows(app).allElementsBoundByIndex.compactMap { $0.label }
        XCTAssertTrue(labels.contains { $0.hasPrefix("Alma G. practiced Confidence Boost") },
                      "Expected 'Alma G. practiced Confidence Boost', got \(labels)")
        XCTAssertTrue(labels.contains { $0.hasPrefix("You practiced Morning Mobility") },
                      "Your own line should read 'You', got \(labels)")
        XCTAssertTrue(labels.contains { $0.hasPrefix("Nia practiced Golden Turmeric Broth") },
                      "A single-word name is shown as-is, got \(labels)")
        XCTAssertEqual(rows(app).count, 6, "The fixture has six finished practices")
        XCTAssertTrue(app.staticTexts["Today"].exists && app.staticTexts["Yesterday"].exists
                      && app.staticTexts["Earlier"].exists,
                      "The feed groups by day: Today, Yesterday, Earlier")
        shot(app, "01-feed-all")

        element(app, "community-scope-friends").tap()
        // Alma and Theo are friends; Nia (pending, asked you) and Mateo
        // (pending, you asked) are not — and neither are you.
        let friendsOnly = rows(app)
        XCTAssertTrue(friendsOnly.firstMatch.waitForExistence(timeout: 10))
        let after = friendsOnly.allElementsBoundByIndex.compactMap { $0.label }
        XCTAssertEqual(after.count, 3, "Friends should narrow six lines to Alma's two and Theo's one, got \(after)")
        XCTAssertFalse(after.contains { $0.hasPrefix("You ") || $0.hasPrefix("Nia ") || $0.hasPrefix("Mateo ") },
                       "Friends must show friends only, got \(after)")
        shot(app, "02-feed-friends")
    }

    /// Accepting a request on the Friends screen moves the person to Friends,
    /// and the badge on the tab's Friends button goes with it.
    func testAcceptingARequestMakesAFriend() {
        let app = launch(fixture: true)

        let friendsButton = element(app, "community-friends")
        XCTAssertTrue(friendsButton.waitForExistence(timeout: 15))
        XCTAssertTrue(friendsButton.label.contains("1 request"),
                      "One request is waiting in the fixture, got '\(friendsButton.label)'")
        friendsButton.tap()

        let accept = app.buttons["Accept"].firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 10), "The waiting request never appeared")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "friend-row").count, 2,
                       "Two friends before accepting")
        shot(app, "03-friends-with-request")
        accept.tap()

        let friendRows = app.descendants(matching: .any).matching(identifier: "friend-row")
        let deadline = Date().addingTimeInterval(10)
        while friendRows.count != 3 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertEqual(friendRows.count, 3, "Accepting should make three friends")
        XCTAssertFalse(app.buttons["Accept"].exists, "The request should be gone once accepted")
        shot(app, "04-friends-after-accept")

        // Search finds a member by name and offers Add for someone new.
        let search = element(app, "friends-search")
        search.tap()
        if app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            search.typeText("Mat")
            let result = element(app, "search-result")
            XCTAssertTrue(result.waitForExistence(timeout: 10), "Search for 'Mat' should find Mateo")
            XCTAssertTrue(app.staticTexts["Requested"].exists,
                          "Mateo already has a request from you, so the control reads Requested")
            shot(app, "05-search")
        }

        // Back on the tab, no badge. (Not `app.buttons["Community"]` — that
        // also matches the bottom nav's tab, hidden under the pushed screen.)
        element(app, "back-bar").tap()
        XCTAssertTrue(friendsButton.waitForExistence(timeout: 10))
        XCTAssertFalse(friendsButton.label.contains("request"), "No requests left, so no badge")
    }

    /// The feed is browsing and stays open; Friends is personal and is not.
    func testGuestChoosingFriendsIsAskedToSignIn() {
        let app = launch(fixture: false)

        let friendsScope = element(app, "community-scope-friends")
        XCTAssertTrue(friendsScope.waitForExistence(timeout: 20), "The scope toggle never appeared")
        shot(app, "06-guest-feed")
        friendsScope.tap()

        let close = app.buttons["account-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), """
            Choosing Friends as a guest did not raise the account sheet. The \
            friendships policy refuses anonymous guests, so a gate that fails \
            open surfaces as an empty list instead of a sign-in.
            """)
        shot(app, "07-account-sheet-on-friends")
        close.tap()

        // Still on All — the choice was not made behind the sheet.
        XCTAssertTrue(friendsScope.waitForExistence(timeout: 10))
        XCTAssertFalse(friendsScope.isSelected, "Dismissing the sheet must leave the guest on All")
        XCTAssertTrue(element(app, "community-scope-all").isSelected)

        // And the Friends button asks the same.
        element(app, "community-friends").tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10), "The Friends screen must be behind the gate too")
        shot(app, "08-account-sheet-on-friends-screen")
    }
}
