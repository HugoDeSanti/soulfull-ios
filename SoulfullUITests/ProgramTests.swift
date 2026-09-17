//
//  ProgramTests.swift
//  SoulfullUITests
//
//  The Programs tab, driven end to end.
//
//  These earn their place for the same reason `RetreatBrochureTests` does: the
//  curriculum decode **fails soft**. A malformed `programs.curriculum` doesn't
//  throw — `ProgramRow.decodedCurriculum` logs it and returns nil, and the
//  program then renders as one with no days authored yet. That is indis-
//  tinguishable from an empty column by inspection, by reasoning about the
//  code, or by any test that stops at the network layer. Only looking at the
//  screen catches it.
//
//  The third test guards the gate: enrolling is the one thing on this tab that
//  needs an account, and the RLS policy behind it refuses anonymous guests, so
//  a gate that failed open would produce a bare error rather than a sign-in
//  sheet.
//

import XCTest

final class ProgramTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchOnProgramsTab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", "programs"]
        app.launch()
        return app
    }

    /// The catalog comes from Supabase, filtered to `published`. No fixture is
    /// involved — `-preview-programs` is deliberately NOT passed.
    func testProgramsTabListsAPublishedProgramFromTheDatabase() {
        let app = launchOnProgramsTab()

        let card = app.buttons.matching(identifier: "program-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 25),
                      "No program card appeared — the catalog fetch, the `published` filter, or the seed is wrong")
        shot(app, "01-programs-catalog")
    }

    /// The fail-soft guard. A broken curriculum renders as a program with no
    /// days and no error, so the assertion has to be on the days themselves.
    func testProgramDetailRendersDaysDecodedFromTheCurriculum() {
        let app = launchOnProgramsTab()

        let card = app.buttons.matching(identifier: "program-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 25), "Programs catalog never appeared")
        card.tap()

        let days = app.buttons.matching(identifier: "program-day-row")
        XCTAssertTrue(days.firstMatch.waitForExistence(timeout: 15), """
            The program rendered no days. The curriculum either failed to decode \
            (check the log for "unreadable curriculum" — it fails soft, so the \
            screen looks identical to an unauthored program) or the column is empty.
            """)
        shot(app, "02-program-detail-days")

        // More than one, because a single row could be a coincidence of layout
        // rather than a decoded list.
        XCTAssertGreaterThan(days.count, 1, "Only one day decoded — the curriculum is partially readable")
    }

    /// The cross-tab hand-off: Home's "Digital Retreats" shelf sets
    /// `pendingProgram`, `MainTabView` switches tab, and `ProgramsRoot`
    /// consumes it on appear. Three components, none of which fails loudly —
    /// a dropped hand-off just lands you on the Programs landing instead, which
    /// looks like a working tap.
    func testHomeShelfOpensTheProgramInTheProgramsTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", "home"]
        app.launch()

        let all = app.buttons["All programs"]
        XCTAssertTrue(all.waitForExistence(timeout: 30), "Home never finished loading")

        // The shelf is the last section; scroll it into view before tapping.
        var tries = 0
        while !all.isHittable && tries < 6 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        XCTAssertTrue(all.isHittable, "The Digital Retreats shelf never scrolled into reach")
        shot(app, "06-home-shelf")
        all.tap()

        // Landed on the Programs tab.
        let card = app.buttons.matching(identifier: "program-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Tapping ALL did not reach the Programs tab")
        shot(app, "07-handed-off-to-programs-tab")
    }

    /// Browsing is open all the way down to the day list; joining is not.
    func testGuestTappingStartIsAskedToSignInBeforeJoining() {
        let app = launchOnProgramsTab()

        let card = app.buttons.matching(identifier: "program-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 25), "Programs catalog never appeared")
        card.tap()

        let start = app.buttons["Start this program"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "The join CTA never appeared")
        shot(app, "03-detail-as-guest")
        start.tap()

        let close = app.buttons["account-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), """
            Tapping "Start this program" as a guest did not raise the account sheet. \
            The RLS policy refuses anonymous guests, so a gate that fails open \
            surfaces as a bare error instead of a sign-in.
            """)
        shot(app, "04-account-sheet-on-join")

        // And nothing was joined behind the sheet: dismissing returns to the
        // un-enrolled detail screen, CTA intact.
        close.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10),
                      "After dismissing the account sheet the join CTA should still be there, un-enrolled")
        shot(app, "05-still-not-enrolled")
    }
}
