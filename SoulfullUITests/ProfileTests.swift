//
//  ProfileTests.swift
//  SoulfullUITests
//
//  The You tab: practice numbers, and the retreats a member has been on.
//
//  The numbers are the part worth guarding. Each one rests on a definition
//  (what counts as a class, what makes a day count toward a streak — see
//  `PracticeStats`) and every one of those definitions fails *quietly*: count
//  a journal entry as a class, or an opened-but-unfinished practice as a day,
//  and the screen still shows a plausible number. So the member test runs
//  against a fixture built to separate right from nearly-right — it holds the
//  practices that must NOT count alongside the ones that must — and asserts
//  exact values.
//

import XCTest

final class ProfileTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchWithFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-preview-you"]
        app.launch()
        return app
    }

    private func value(_ element: XCUIElement) -> String? {
        element.value as? String
    }

    /// Any element type: a combined card surfaces as StaticText or Other
    /// depending on what's inside it, and that's not what these tests are about.
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// `isHittable` is true for a row sitting under the floating nav bar — it
    /// is on screen, just covered — so a tap there lands on the nav. Scroll
    /// until the row clears it.
    private func scrollClearOfNav(_ row: XCUIElement, in app: XCUIApplication) {
        let limit = app.windows.firstMatch.frame.height - 180
        var tries = 0
        while (!row.exists || row.frame.maxY > limit) && tries < 8 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
    }

    /// A guest can't have practised — every practice is behind the account
    /// gate — so they're shown what an account keeps, not four zeros.
    func testGuestSeesAnInvitationRatherThanNumbers() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", "you"]
        app.launch()

        let invitation = element(app, "guest-invitation")
        XCTAssertTrue(invitation.waitForExistence(timeout: 15), "The guest invitation never appeared")
        XCTAssertFalse(element(app, "stat-current-streak").exists,
                       "A guest was shown practice stats they can't have")
        XCTAssertTrue(app.buttons["Create account"].exists, "A guest needs a way to make an account from here")
        shot(app, "01-you-as-guest")
    }

    /// The fixture (`ProfileViewModel.installPreviewFixture`) is 4 days of
    /// movement up to today, a 9-day run of sessions a month back, plus a
    /// finished journal entry and recipe (practice days, not classes), an
    /// unfinished session (minutes, not a class) and an opened-but-unfinished
    /// prompt (nothing at all).
    func testMemberStatsAreComputedFromTheLedger() {
        let app = launchWithFixture()

        let streak = element(app, "stat-current-streak")
        XCTAssertTrue(streak.waitForExistence(timeout: 15), "The stats grid never appeared")
        shot(app, "02-you-member-top")

        XCTAssertEqual(value(streak), "4 days, You've completed a practice today",
                       "Current streak: today and the three days before")
        XCTAssertEqual(value(element(app, "stat-best-streak")), "9 days, Days in a row",
                       "Best streak: the 9-day run a month back — longer than the current one")
        XCTAssertEqual(value(element(app, "stat-classes")), "13, Sessions & movement",
                       "Classes: 4 movement + 9 sessions. A journal entry, a recipe or an unfinished sitting is not a class")
        XCTAssertEqual(value(element(app, "stat-minutes")), "250, 4 hr, 10 min",
                       "Minutes: 60 + 180 + the unfinished session's 10. Journal and recipe time don't count")
    }

    /// Practised today but finished nothing. Only a finished practice keeps a
    /// streak, so today doesn't count yet — but the member DID practise, and
    /// being told "Practice today to keep it" straight after reads as though it
    /// never happened. The caption has to say what's actually true.
    func testStreakCaptionAcknowledgesAnUnfinishedPracticeToday() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded",
                               "-preview-you", "-preview-you-unfinished"]
        app.launch()

        let streak = element(app, "stat-current-streak")
        XCTAssertTrue(streak.waitForExistence(timeout: 15), "The stats grid never appeared")
        shot(app, "05-you-unfinished-today")

        XCTAssertEqual(value(streak), "3 days, Finish a practice today to keep your streak", """
            Today's practice is unfinished, so the streak rests on the three days             before it — and the caption must acknowledge today's practice rather             than tell them to practise.
            """)
        XCTAssertFalse(value(streak)?.contains("Practice today") ?? true,
                       "Told someone who practised today to practise today")
        XCTAssertEqual(value(element(app, "stat-classes")), "12, Sessions & movement",
                       "An unfinished movement sitting is not a class")
        XCTAssertEqual(value(element(app, "stat-minutes")), "250, 4 hr, 10 min",
                       "Unfinished time still counts as minutes practiced")
    }

    /// One program in progress, one completed; two retreats whose last day has
    /// passed.
    func testMemberHistoryListsProgramsAndPastRetreats() {
        let app = launchWithFixture()

        XCTAssertTrue(element(app, "stat-current-streak").waitForExistence(timeout: 15))

        let journeys = app.descendants(matching: .any).matching(identifier: "journey-row")
        let retreats = app.descendants(matching: .any).matching(identifier: "past-retreat-row")

        scrollClearOfNav(retreats.element(boundBy: 1), in: app)
        shot(app, "03-you-member-history")

        XCTAssertEqual(journeys.count, 2, "Expected one program in progress and one completed")
        XCTAssertEqual(retreats.count, 2, "Expected the two past retreats from the fixture")
    }

    /// The hand-off: a program row sets `pendingProgram`, `MainTabView`
    /// switches tab, and `ProgramsRoot` consumes it. Like Home's shelf, a
    /// dropped hand-off fails silently — you'd land on the Programs landing and
    /// it would look like a working tap — so assert on a screen *inside* the
    /// program. It lands on the open day or on the program itself, depending on
    /// whether the day is open; either proves the hand-off.
    func testProgramRowOpensItInTheProgramsTab() {
        let app = launchWithFixture()

        let row = app.buttons.matching(identifier: "journey-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No tappable program row")
        scrollClearOfNav(row, in: app)
        row.tap()

        let day = app.descendants(matching: .any).matching(identifier: "program-activity-row").firstMatch
        let detail = app.descendants(matching: .any).matching(identifier: "program-day-row").firstMatch
        let deadline = Date().addingTimeInterval(25)
        while !(day.exists || detail.exists), Date() < deadline {
            _ = day.waitForExistence(timeout: 1)
        }
        shot(app, "04-handed-off-to-program")
        XCTAssertTrue(day.exists || detail.exists, """
            Tapping a program on the You tab didn't open it in the Programs tab.             Check the pendingProgram hand-off — dropped, it just lands on the             Programs landing.
            """)
    }
}
