//
//  GatheringsTabTests.swift
//  SoulfullUITests
//
//  The Gatherings tab — the retreats stack as a tab root — and the two ways
//  Home hands off to it: the shelf's "All gatherings", and a card on the shelf.
//
//  Like the digital retreats hand-off, neither fails loudly. A dropped pending
//  retreat lands on the stack instead of the retreat, which looks like a
//  working tap; a card pinned to the stack's foot without clearing the tab bar
//  is still "there", just under the bar. So each is asserted on what the
//  member would actually see.
//
//  Asserts on structure, never on which retreats exist — the catalog is data.
//

import XCTest

final class GatheringsTabTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", tab]
        app.launch()
        return app
    }

    /// The "01 / 04" folio, read through its VoiceOver label — only the stack
    /// has one, so finding it means the stack is on screen.
    private func folio(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Retreat "))
            .firstMatch
    }

    /// The underlined Back link at the top of a pushed screen.
    private func back(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Back")).firstMatch
    }

    /// One button per name in the stack, labelled "<name>, <country>" (see
    /// `RetreatsStackTests.rows`).
    private func rows(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons
            .matching(NSPredicate(format: "label MATCHES %@", "^[^,]+, [^,]+$"))
            .allElementsBoundByIndex
    }

    private func waitForLabel(_ element: XCUIElement, toSatisfy test: @escaping (String) -> Bool,
                              timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, test(element.label) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    /// Scrolls Home until `element`'s centre — where `tap()` lands — sits
    /// above the docked bar. The gatherings shelf is the last thing on the
    /// page. An element under the bar still reports hittable, and the tap
    /// would land on a tab.
    private func scrollHome(to element: XCUIElement, _ app: XCUIApplication) {
        let floor = app.windows.firstMatch.frame.maxY - 140
        var tries = 0
        while (!element.isHittable || element.frame.midY > floor) && tries < 8 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        XCTAssertTrue(element.isHittable && element.frame.midY <= floor,
                      "Home's gatherings shelf never scrolled clear of the tab bar")
    }

    /// As a tab root the stack has nothing to go back to, and the card pinned
    /// to its foot has to sit above the docked bar rather than under it.
    func testGatheringsTabIsTheStackWithItsCardClearOfTheBar() throws {
        let app = launch(tab: "gatherings")

        XCTAssertTrue(folio(app).waitForExistence(timeout: 30), "The retreats stack never loaded")
        XCTAssertTrue(app.buttons["Gatherings"].isSelected, "The Gatherings tab isn't the selected one")
        XCTAssertFalse(back(app).exists, "A tab root has nothing to go back to")

        let explore = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Explore "))
            .firstMatch
        XCTAssertTrue(explore.waitForExistence(timeout: 10), "The stack's card never appeared")
        let bar = app.buttons["Gatherings"].frame
        XCTAssertLessThanOrEqual(explore.frame.maxY, bar.minY,
                                 "The card sits under the tab bar: card \(explore.frame), bar item \(bar)")
        shot(app, "01-gatherings-tab")

        explore.tap()
        XCTAssertTrue(app.buttons["Request a place"].waitForExistence(timeout: 15),
                      "The card didn't open the retreat")
    }

    /// A tab keeps its state while another is showing. Tabs used to be rebuilt
    /// from blank on every tap, which flashed the empty state ("New gatherings
    /// are on their way") before the catalog arrived and dropped the member
    /// back on the first retreat. The flash is too quick to catch here; the
    /// stack still being where it was left is the proof the tab wasn't rebuilt.
    func testTheStackKeepsItsPlaceAcrossATabSwitch() throws {
        let app = launch(tab: "gatherings")
        let folio = folio(app)
        XCTAssertTrue(folio.waitForExistence(timeout: 30), "The retreats stack never loaded")
        let names = rows(app)
        guard names.count >= 2 else {
            throw XCTSkip("Needs two upcoming retreats to scroll between; the catalog has \(names.count)")
        }
        names[0].swipeUp(velocity: .slow)
        XCTAssertTrue(waitForLabel(folio) { !$0.hasPrefix("Retreat 1 of") },
                      "Scrolling didn't move the focus — folio still reads \(folio.label)")
        let leftOn = folio.label
        shot(app, "05-stack-scrolled")

        app.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["Home"].isSelected, "The Home tab didn't open")
        app.buttons["Gatherings"].tap()

        XCTAssertTrue(folio.waitForExistence(timeout: 5), "The stack wasn't there on coming back")
        XCTAssertFalse(app.staticTexts["New gatherings are on their way"].exists,
                       "Coming back to the tab showed the empty catalog")
        XCTAssertEqual(folio.label, leftOn, "Coming back to the tab rebuilt the stack from the top")
        shot(app, "06-stack-after-tab-switch")
    }

    /// The shelf hand-off into a Gatherings tab that is already open (and so
    /// already has its catalog). The retreat is pushed in the same update the
    /// tab comes back, the case that once pinned the CPU at 100% on a stack
    /// that had never been on screen.
    func testHomeShelfCardOpensTheRetreatInAnAlreadyOpenGatheringsTab() {
        let app = launch(tab: "gatherings")
        XCTAssertTrue(folio(app).waitForExistence(timeout: 30), "The retreats stack never loaded")

        app.buttons["Home"].tap()
        let card = app.buttons
            .matching(NSPredicate(format: "label ENDSWITH %@", " guests"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "No retreat card on Home")
        scrollHome(to: card, app)
        card.tap()

        XCTAssertTrue(app.buttons["Request a place"].waitForExistence(timeout: 15),
                      "Tapping a retreat on Home didn't open it in the open Gatherings tab")
        shot(app, "07-retreat-from-home-into-open-tab")

        back(app).tap()
        XCTAssertTrue(folio(app).waitForExistence(timeout: 15), "Back from the retreat didn't land on the stack")
        XCTAssertTrue(app.buttons["Gatherings"].isSelected, "Back landed outside the Gatherings tab")
    }

    /// Home's "All gatherings" switches to the tab rather than pushing a second
    /// copy of the stack onto Home.
    func testHomeShelfAllOpensTheGatheringsTab() {
        let app = launch(tab: "home")

        let all = app.buttons["All gatherings"]
        XCTAssertTrue(all.waitForExistence(timeout: 30), "Home never finished loading")
        scrollHome(to: all, app)
        shot(app, "02-home-gatherings-shelf")
        all.tap()

        XCTAssertTrue(folio(app).waitForExistence(timeout: 15), "Tapping ALL didn't reach the stack")
        XCTAssertTrue(app.buttons["Gatherings"].isSelected, "ALL reached a stack, but not the Gatherings tab's")
        shot(app, "03-handed-off-to-gatherings")
    }

    /// A card on the shelf opens that retreat inside the Gatherings tab, and
    /// Back from it lands on the stack — not on Home, and not on nothing.
    func testHomeShelfCardOpensTheRetreatInTheGatheringsTab() {
        let app = launch(tab: "home")

        // Retreat cards read "<name>, <country>. <dates>. N days, N guests".
        let card = app.buttons
            .matching(NSPredicate(format: "label ENDSWITH %@", " guests"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "No retreat card on Home")
        scrollHome(to: card, app)
        card.tap()

        XCTAssertTrue(app.buttons["Request a place"].waitForExistence(timeout: 15), """
            Tapping a retreat on Home didn't open it. Check the pendingRetreat \
            hand-off — dropped, it just lands on the stack.
            """)
        shot(app, "04-retreat-from-home")

        back(app).tap()
        XCTAssertTrue(folio(app).waitForExistence(timeout: 15), "Back from the retreat didn't land on the stack")
        XCTAssertTrue(app.buttons["Gatherings"].isSelected, "Back landed outside the Gatherings tab")
    }
}
