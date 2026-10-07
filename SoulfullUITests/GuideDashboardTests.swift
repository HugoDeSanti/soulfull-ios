//
//  GuideDashboardTests.swift
//  SoulfullUITests
//
//  A guide's dashboard: the card on their You tab and the sheet it opens.
//
//  Runs against `-preview-guide` (`GuideDashboardViewModel.previewFixture`):
//  this month 86 people and 1,203 of 9,700 minutes heard from a $2,500 pool,
//  an estimate of $310.05; four past months, two of them paid ($380.14 in
//  all), one due and one with no pool set. `-preview-guide-pending` leaves this
//  month's pool unset, which must show the share and no amount. A member who
//  isn't a guide must never see the card.
//

import XCTest

@MainActor
final class GuideDashboardTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", "you", "-preview-you"] + extra
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func scrollUntilVisible(_ target: XCUIElement, in app: XCUIApplication) {
        let limit = app.windows.firstMatch.frame.height - 120
        var tries = 0
        while (!target.exists || target.frame.maxY > limit) && tries < 10 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
    }

    func testGuideCardOpensTheirDashboard() {
        let app = launch(["-preview-guide"])

        let card = element(app, "guide-dashboard-card")
        XCTAssertTrue(card.waitForExistence(timeout: 15), "A linked guide's You tab never showed the dashboard card")
        XCTAssertTrue(card.label.contains("86"), "The card should show this month's people: \(card.label)")
        XCTAssertTrue(card.label.contains("$310.05"), "The card should show this month's estimate: \(card.label)")
        shot(app, "01-you-tab-guide-card")

        card.tap()

        let thisMonth = element(app, "guide-this-month")
        XCTAssertTrue(thisMonth.waitForExistence(timeout: 10), "The dashboard never opened")
        XCTAssertTrue(thisMonth.label.contains("$310.05"), "This month's estimate: \(thisMonth.label)")
        XCTAssertTrue(thisMonth.label.contains("Estimate"), "A running month must say it's an estimate: \(thisMonth.label)")
        XCTAssertTrue(thisMonth.label.contains("12.4%"), "The share behind the estimate: \(thisMonth.label)")
        shot(app, "02-dashboard-top")

        let people = element(app, "guide-people-total")
        scrollUntilVisible(people, in: app)
        XCTAssertTrue(people.label.contains("212"), "All-time people: \(people.label)")
        shot(app, "03-dashboard-people")

        let paid = element(app, "guide-paid-to-date")
        scrollUntilVisible(paid, in: app)
        XCTAssertTrue(paid.label.contains("$380.14"), "Paid to date adds the paid months only: \(paid.label)")

        let months = app.descendants(matching: .any).matching(identifier: "guide-month-row")
        XCTAssertEqual(months.count, 4, "Every closed month is listed, quiet or not")
        let labels = (0..<months.count).map { months.element(boundBy: $0).label }
        XCTAssertTrue(labels.contains { $0.contains("Paid") && $0.contains("$284.09") }, "Last month, paid: \(labels)")
        XCTAssertTrue(labels.contains { $0.contains("To be paid") && $0.contains("$198.40") }, "A month owed: \(labels)")
        XCTAssertTrue(labels.contains { $0.contains("Pool not set") }, "A month with no pool shows no amount: \(labels)")
        shot(app, "04-dashboard-months")

        let practice = element(app, "guide-practice-row")
        scrollUntilVisible(practice, in: app)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "guide-practice-row").count, 4)
        XCTAssertTrue(practice.label.contains("Breath of Fire"), "Most-reached practice first: \(practice.label)")
        scrollUntilVisible(element(app, "guide-program-row"), in: app)
        shot(app, "05-dashboard-practices")

        let close = element(app, "guide-dashboard-close")
        XCTAssertTrue(close.isHittable, "The close button should stay reachable at any scroll")
        close.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Closing should return to the You tab")
    }

    func testAMonthWithNoPoolShowsTheShareAndNoAmount() {
        let app = launch(["-preview-guide", "-preview-guide-pending"])

        let card = element(app, "guide-dashboard-card")
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(card.label.contains("Pending"), "No pool, no amount: \(card.label)")
        XCTAssertFalse(card.label.contains("$"), "Nothing may be estimated from a pool that isn't set: \(card.label)")

        card.tap()

        let thisMonth = element(app, "guide-this-month")
        XCTAssertTrue(thisMonth.waitForExistence(timeout: 10))
        XCTAssertTrue(thisMonth.label.contains("12.4%"), "The share stands in for the amount: \(thisMonth.label)")
        XCTAssertTrue(thisMonth.label.contains("Pool not set"), "\(thisMonth.label)")
        XCTAssertFalse(thisMonth.label.contains("$"), "No amount while the pool isn't set: \(thisMonth.label)")
        shot(app, "06-dashboard-pool-pending")
    }

    /// The simulator is signed out, so the live `guide_dashboard()` answers no
    /// row (or isn't there at all): either way, no card.
    func testAMemberWhoIsNotAGuideSeesNoCard() {
        let app = launch()

        XCTAssertTrue(element(app, "stat-current-streak").waitForExistence(timeout: 15),
                      "The member layout never appeared")
        XCTAssertFalse(element(app, "guide-dashboard-card").waitForExistence(timeout: 6),
                       "A member who isn't a guide was shown the guide dashboard")
        shot(app, "07-you-tab-not-a-guide")
    }
}
