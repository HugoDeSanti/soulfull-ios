//
//  CommunityTests.swift
//  SoulfullUITests
//
//  The Community tab: the feed reads as sentences with a face beside each,
//  the All | Friends toggle actually narrows it, the Friends screen moves a
//  request from waiting to accepted, a friend's row carries their streak and
//  opens their numbers, and a guest reaching for Friends is asked to sign in —
//  not shown an empty list or a bare error.
//
//  The populated screens run against the `-preview-community` fixture, which
//  holds four members (one of them "you"), six finished practices, two
//  friends (Alma kept a 12-day streak today; Theo's 3 days end yesterday), one
//  request waiting on you (Nia, who keeps her practice private) and one you
//  sent. The guest test runs against the live backend, where the gate is the
//  thing under test.
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

    private func value(_ element: XCUIElement) -> String? {
        element.value as? String
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
        XCTAssertTrue(friendRows.allElementsBoundByIndex.contains { $0.label == "Nia, keeps their practice private" },
                      "Nia shares no numbers, and her row should say so, got \(friendRows.allElementsBoundByIndex.map { $0.label })")
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

    /// A friend's row says their streak and classes; it opens their page, where
    /// the four numbers of their own You tab are; and they can be removed from
    /// there, which closes the page.
    func testAFriendsRowAndPageShowTheirPractice() {
        let app = launch(fixture: true)

        let friendsButton = element(app, "community-friends")
        XCTAssertTrue(friendsButton.waitForExistence(timeout: 15))
        friendsButton.tap()

        let friendRows = app.descendants(matching: .any).matching(identifier: "friend-row")
        XCTAssertTrue(friendRows.firstMatch.waitForExistence(timeout: 10), "No friends on the Friends screen")
        let labels = friendRows.allElementsBoundByIndex.map { $0.label }
        XCTAssertTrue(labels.contains("Alma G., 12-day streak · 48 classes"),
                      "Alma's row should carry her streak and classes, got \(labels)")
        XCTAssertTrue(labels.contains("Theo R., 3-day streak · 7 classes"),
                      "Theo's streak ended yesterday and is still alive, got \(labels)")
        shot(app, "06-friends-with-numbers")

        let alma = friendRows.matching(NSPredicate(format: "label BEGINSWITH 'Alma G.'")).firstMatch
        alma.tap()

        let name = element(app, "friend-name")
        XCTAssertTrue(name.waitForExistence(timeout: 10), "Alma's row didn't open her page")
        XCTAssertEqual(name.label, "Alma G.")
        let streak = element(app, "friend-stat-current-streak")
        XCTAssertTrue(streak.waitForExistence(timeout: 5))
        XCTAssertEqual(value(streak), "12 days, Practiced today")
        XCTAssertEqual(value(element(app, "friend-stat-best-streak")), "21 days, Days in a row")
        XCTAssertEqual(value(element(app, "friend-stat-classes")), "48, Sessions & movement")
        XCTAssertEqual(value(element(app, "friend-stat-minutes"))?.hasPrefix("612, "), true,
                       "612 minutes in class, got \(value(element(app, "friend-stat-minutes")) ?? "nothing")")
        shot(app, "07-friend-page")

        element(app, "friend-remove").tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Remove friend' AND identifier != 'friend-remove'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Remove went through without asking")
        shot(app, "08-remove-confirm")
        confirm.tap()

        XCTAssertTrue(friendRows.firstMatch.waitForExistence(timeout: 10), "Removing should close her page")
        let deadline = Date().addingTimeInterval(10)
        while friendRows.count != 1 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertEqual(friendRows.count, 1, "Only Theo should be left")
        XCTAssertFalse(friendRows.matching(NSPredicate(format: "label BEGINSWITH 'Alma G.'")).firstMatch.exists)
        shot(app, "09-after-remove")
    }

    /// A like moves the count at once and can be taken back; your own line
    /// has no button; the bell counts unread likes and clears once seen.
    func testLikesMoveTheCountAndNotificationsClearTheBadge() {
        let app = launch(fixture: true)

        let first = rows(app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), "The feed never rendered")
        let allRows = rows(app).allElementsBoundByIndex
        // Alma's Confidence Boost leads: 3 likes, already liked by you.
        let almaLike = allRows[0].descendants(matching: .any).matching(identifier: "like-button").firstMatch
        XCTAssertEqual(almaLike.label, "Unlike")
        XCTAssertEqual(value(almaLike), "3 likes")
        // Your own line has no button.
        XCTAssertEqual(allRows[1].descendants(matching: .any).matching(identifier: "like-button").count, 0,
                       "You can't like your own practice")
        // Theo's: 1 like, not yours. Like it, then take it back.
        let theoLike = allRows[2].descendants(matching: .any).matching(identifier: "like-button").firstMatch
        XCTAssertEqual(theoLike.label, "Like")
        XCTAssertEqual(value(theoLike), "1 like")
        theoLike.tap()
        XCTAssertTrue(theoLike.waitForExistence(timeout: 5))
        XCTAssertEqual(theoLike.label, "Unlike", "A tap likes")
        XCTAssertEqual(value(theoLike), "2 likes", "…and the count moves with it")
        shot(app, "09-liked")
        theoLike.tap()
        XCTAssertEqual(theoLike.label, "Like", "A second tap unlikes")
        XCTAssertEqual(value(theoLike), "1 like")

        // The bell: one unread in the fixture.
        let bell = element(app, "community-notifications")
        XCTAssertTrue(bell.exists)
        XCTAssertTrue(bell.label.contains("1 unread"), "got '\(bell.label)'")
        bell.tap()

        let note = app.descendants(matching: .any).matching(identifier: "notification-row").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), "The notification never appeared")
        XCTAssertTrue(note.label.hasPrefix("Alma G. liked your Morning Mobility practice"), "got '\(note.label)'")
        XCTAssertTrue(note.label.hasSuffix(", new"), "The unread one is marked new for this visit")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "notification-row").count, 2)
        shot(app, "10-notifications")

        element(app, "back-bar").tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        XCTAssertFalse(bell.label.contains("unread"), "Seen, so no badge: got '\(bell.label)'")
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
        close.tap()

        // So does a like — when the live feed has a line to like.
        let like = element(app, "like-button")
        if like.waitForExistence(timeout: 5) {
            like.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 10), "Liking as a guest must raise the account sheet")
            close.tap()
            XCTAssertEqual(like.label, "Like", "Nothing was liked behind the sheet")
        }
    }
}
