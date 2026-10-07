//
//  RetreatsStackTests.swift
//  SoulfullUITests
//
//  Drives the retreats stack as it ships, the Gatherings tab's root, against
//  the live catalog. Not through `-preview-retreats`: that harness shows the
//  stack outside the tab (a Back button, no room for the bar), which the app
//  itself never does.
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
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", "gatherings"]
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
        // stack on that retreat. The name is read first: in the catalog the
        // stack's rows leave the accessibility tree (VoiceOver used to meet
        // every retreat twice), so they can't be read from there.
        let lastName = names[count - 1].label
        let toggle = app.buttons["Show all retreats"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "No catalog toggle")
        toggle.tap()
        XCTAssertTrue(app.buttons["Show as a list"].waitForExistence(timeout: 5),
                      "The toggle didn't flip to its list state")
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

        // The pinch reaches the same place as the toggle. On a name in the
        // stack, not on `app`: a pinch across the whole screen starts one
        // finger on the docked tab bar, whose button takes it, and the stack
        // only ever feels one finger.
        let onScreenName = try XCTUnwrap(rows(app).first { $0.isHittable }, "No name on screen to pinch on")
        onScreenName.pinch(withScale: 0.4, velocity: -2)
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
        // The accessibility frame is the hit frame. On iOS 26 the glass under
        // the card is not hit-testable, and before it had a content shape the
        // frame shrank to the text and the pill — the empty middle, which is
        // exactly where a thumb lands, did nothing.
        let screenWidth = app.windows.firstMatch.frame.width
        XCTAssertGreaterThan(explore.frame.width, screenWidth * 0.85,
                             "The card only answers taps on its text: \(explore.frame)")
        explore.tap()

        XCTAssertTrue(app.buttons["Request a place"].waitForExistence(timeout: 10),
                      "The card didn't open the retreat")
        shot(app, "05-detail")

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Back")).firstMatch.tap()
        XCTAssertTrue(folio.waitForExistence(timeout: 5), "Back from the detail didn't return to the stack")
    }
}
