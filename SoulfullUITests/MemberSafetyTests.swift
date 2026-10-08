//
//  MemberSafetyTests.swift
//  SoulfullUITests
//
//  Report and Block (Guideline 1.2), as a reviewer would find them: the "⋯"
//  beside another member's line offers both; a report can't go without a
//  reason, sends, promises a review within 24 hours and offers Block; Block
//  asks first and then takes every line of theirs off the feed; a guest can
//  report but is asked to sign in to block; and the You tab lists who you've
//  blocked, with Unblock.
//
//  The member journeys run against the `-preview-community` / `-preview-you`
//  fixtures (no report reaches the team, no block reaches the server). The
//  guest journey runs against the live feed, where the gate is what's under
//  test. The server's half — RLS, the views, the cooldown, `report-member` —
//  is verified live per 0028's header.
//

import XCTest

@MainActor
final class MemberSafetyTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "activity-row")
    }

    private func row(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func launchFeed(fixture: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", "community"]
        if fixture { app.launchArguments.append("-preview-community") }
        app.launch()
        return app
    }

    /// Opens the "⋯" on a row and picks one of its items.
    private func choose(_ item: String, on row: XCUIElement, in app: XCUIApplication) {
        let menu = row.descendants(matching: .any).matching(identifier: "member-menu").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "No ⋯ beside \(row.label)")
        menu.tap()
        let button = app.buttons[item]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The ⋯ menu offered no '\(item)'")
        button.tap()
    }

    func testReportingALineSendsItAndOffersBlock() {
        let app = launchFeed(fixture: true)
        let theo = row(app, startingWith: "Theo R.")
        XCTAssertTrue(theo.waitForExistence(timeout: 15), "The feed never rendered")
        XCTAssertEqual(element(app, "member-menu").exists, true)
        // Your own line has no ⋯: there is no one to report or block.
        let mine = row(app, startingWith: "You practiced")
        XCTAssertFalse(mine.descendants(matching: .any).matching(identifier: "member-menu").firstMatch.exists,
                       "Your own line offered Report / Block")

        choose("Report Theo R.", on: theo, in: app)
        let send = element(app, "report-send")
        XCTAssertTrue(send.waitForExistence(timeout: 5), "The Report sheet never opened")
        XCTAssertFalse(send.isEnabled, "A report could be sent without a reason")
        shot(app, "01-report-sheet")

        element(app, "report-reason-harassment").tap()
        XCTAssertTrue(send.isEnabled, "Choosing a reason didn't make the report sendable")
        send.tap()

        XCTAssertTrue(app.staticTexts["Thank you"].waitForExistence(timeout: 10), "The report never confirmed")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '24 hours'")).firstMatch.exists,
                      "The confirmation should say when the team will look")
        shot(app, "02-report-sent")

        element(app, "report-block").tap()
        // Theo's one line goes; the rest of the feed stays.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: row(app, startingWith: "Theo R."))
        waitForExpectations(timeout: 10)
        XCTAssertEqual(rows(app).count, 5, "Blocking Theo should leave the other five lines")
        shot(app, "03-blocked-from-report")
    }

    func testBlockingAsksFirstThenTakesEveryLineOfTheirsAway() {
        let app = launchFeed(fixture: true)
        let alma = row(app, startingWith: "Alma G.")
        XCTAssertTrue(alma.waitForExistence(timeout: 15), "The feed never rendered")
        XCTAssertEqual(rows(app).count, 6)

        choose("Block Alma G.", on: alma, in: app)
        let confirm = app.buttons["Block"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Block went through without asking")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'They won’t be told' OR label CONTAINS \"They won't be told\"")).firstMatch.exists,
                      "The confirmation should say what a block does")
        shot(app, "04-block-confirm")
        confirm.tap()

        expectation(for: NSPredicate(format: "count == 4"), evaluatedWith: rows(app))
        waitForExpectations(timeout: 10)
        XCTAssertFalse(row(app, startingWith: "Alma G.").exists, "A blocked member's line stayed in the feed")
        shot(app, "05-after-block")
    }

    /// A guest can report what they see, but a block needs an account. Runs
    /// against the live feed, so it needs one line from someone sharing.
    func testAGuestCanReportButIsAskedToSignInToBlock() throws {
        let app = launchFeed(fixture: false)
        let line = rows(app).firstMatch
        guard line.waitForExistence(timeout: 20) else {
            throw XCTSkip("The live feed has no line to act on (no member is sharing a finished practice)")
        }
        let name = line.label.components(separatedBy: " practiced").first ?? ""

        choose("Report \(name)", on: line, in: app)
        XCTAssertTrue(element(app, "report-send").waitForExistence(timeout: 5),
                      "A guest should be able to report without an account")
        element(app, "report-close").tap()
        XCTAssertTrue(element(app, "report-send").waitForNonExistence(timeout: 5))

        choose("Block \(name)", on: line, in: app)
        XCTAssertTrue(element(app, "account-close").waitForExistence(timeout: 10),
                      "A guest's Block should raise the account sheet")
        shot(app, "06-guest-block-gate")
        element(app, "account-close").tap()
        XCTAssertFalse(app.buttons["Block"].waitForExistence(timeout: 2),
                       "Closing the account sheet must not carry on into the block")
    }

    func testTheYouTabListsBlockedMembersAndUnblocks() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-preview-you", "-tab", "you"]
        app.launch()

        let open = element(app, "open-blocked-members")
        let limit = app.windows.firstMatch.frame.height - 180
        var tries = 0
        while (!open.exists || open.frame.maxY > limit) && tries < 10 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        XCTAssertTrue(open.exists, "The You tab has no Blocked members row")
        open.tap()

        let unblock = element(app, "unblock")
        XCTAssertTrue(unblock.waitForExistence(timeout: 10), "The fixture's blocked member never appeared")
        XCTAssertTrue(app.staticTexts["Sam K."].exists)
        shot(app, "07-blocked-members")
        unblock.tap()

        XCTAssertTrue(element(app, "blocked-empty").waitForExistence(timeout: 5),
                      "Unblocking the only blocked member should leave the list empty")
        shot(app, "08-unblocked")
        element(app, "blocked-close").tap()
    }
}
