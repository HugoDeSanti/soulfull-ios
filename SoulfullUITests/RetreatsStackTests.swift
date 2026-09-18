//
//  RetreatsStackTests.swift
//  SoulfullUITests
//
//  Drives the retreats stack — the screen behind Home's "All gatherings" —
//  against the live catalog, through the DEBUG `-preview-retreats` hook.
//
//  Asserts on structure, never on which retreats exist: the catalog is data,
//  and which rows are upcoming changes as dates pass.
//

import XCTest

final class RetreatsStackTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-preview-retreats"]
        app.launch()
        return app
    }

    /// The "01 / 04" folio, read through its VoiceOver label.
    private func folio(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Retreat "))
            .firstMatch
    }

    /// One button per name in the stack, labelled "<name>, <country>". The
    /// card under the stack ("Explore …") and the covers carry more commas, so
    /// this matches the rows alone.
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

    /// A row is the retreat's name and nothing else. It used to trail the
    /// guest count as a bare number beside the name.
    func testRowsCarryOnlyTheName() {
        let app = launch()

        XCTAssertTrue(folio(app).waitForExistence(timeout: 30), "The stack never loaded")
        XCTAssertTrue(folio(app).label.hasPrefix("Retreat 1 of"), "The stack didn't open on its first retreat")
        shot(app, "01-stack")

        let names = rows(app)
        XCTAssertFalse(names.isEmpty, "No retreat rows in the stack")
        for row in names {
            XCTAssertNil(row.label.rangeOfCharacter(from: .decimalDigits),
                         "A stack row carries a number: \(row.label)")
        }

        // Nothing on screen is a bare number — that is what the guest count
        // rendered as. (The folio is one element, labelled in words.)
        let bareNumbers = app.staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+$"))
        let found = bareNumbers.allElementsBoundByIndex.map { $0.label }
        XCTAssertTrue(found.isEmpty, "A bare number is on screen: \(found)")
    }

    /// Scroll moves the focus, the catalog refocuses the stack, and the card
    /// opens the focused retreat — with a way back from each.
    func testBrowseRefocusAndOpen() throws {
        let app = launch()

        let folio = folio(app)
        XCTAssertTrue(folio.waitForExistence(timeout: 30), "The stack never loaded")
        let names = rows(app)
        let count = names.count
        guard count >= 2 else {
            throw XCTSkip("Needs two upcoming retreats to scroll between; the catalog has \(count)")
        }

        // Scroll: the focus follows the name on the centre line.
        names[0].swipeUp(velocity: .slow)
        XCTAssertTrue(waitForLabel(folio) { !$0.hasPrefix("Retreat 1 of") },
                      "Scrolling didn't move the focus — folio still reads \(folio.label)")
        shot(app, "02-scrolled")

        // Catalog: the one toggle, then a cover — the last one — refocuses the
        // stack on that retreat.
        let toggle = app.buttons["Show all retreats"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "No catalog toggle")
        toggle.tap()
        XCTAssertTrue(app.buttons["Show as a list"].waitForExistence(timeout: 5),
                      "The toggle didn't flip to its list state")
        let lastName = names[count - 1].label
        let lastCover = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(lastName), "))
            .firstMatch
        XCTAssertTrue(lastCover.waitForExistence(timeout: 5), "No cover for \(lastName)")
        shot(app, "03-catalog")
        lastCover.tap()

        XCTAssertTrue(waitForLabel(folio) { $0 == "Retreat \(count) of \(count)" },
                      "The cover didn't refocus the stack — folio reads \(folio.label)")
        XCTAssertTrue(app.buttons["Show all retreats"].waitForExistence(timeout: 5),
                      "Didn't return to the stack")
        shot(app, "04-refocused")

        // The pinch reaches the same place as the toggle.
        app.pinch(withScale: 0.4, velocity: -2)
        XCTAssertTrue(app.buttons["Show as a list"].waitForExistence(timeout: 5),
                      "Pinching out didn't open the catalog")
        app.buttons["Show as a list"].tap()
        XCTAssertTrue(app.buttons["Show all retreats"].waitForExistence(timeout: 5))

        // The card opens the focused retreat.
        let retreatName = String(lastName.split(separator: ",")[0])
        let explore = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Explore \(retreatName)."))
            .firstMatch
        XCTAssertTrue(explore.waitForExistence(timeout: 5), "The card isn't showing \(retreatName)")
        explore.tap()

        XCTAssertTrue(app.buttons["Request a place"].waitForExistence(timeout: 10),
                      "The card didn't open the retreat")
        shot(app, "05-detail")

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Back")).firstMatch.tap()
        XCTAssertTrue(folio.waitForExistence(timeout: 5), "Back from the detail didn't return to the stack")
    }
}
