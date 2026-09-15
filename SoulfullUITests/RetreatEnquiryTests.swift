//
//  RetreatEnquiryTests.swift
//  SoulfullUITests
//
//  Drives the retreat application end to end.
//
//  Worth a UI test for two reasons. The form is the only way to reach the
//  retreat team from inside the app while reservations are off, so a question
//  that silently stops rendering — or a Submit that never becomes live — costs
//  a booking and looks like nothing at all from the code. And the "still to
//  answer" line is derived state over eleven controls: exactly the kind of
//  logic that reads correctly and behaves otherwise.
//
//  Both tests run against `-preview-enquiry`, which renders the form on a real
//  retreat without driving the whole app to it.
//

import XCTest

final class RetreatEnquiryTests: XCTestCase {

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-preview-enquiry"]
        app.launch()
        return app
    }

    /// Scrolls the form until `element` sits comfortably in the middle of the
    /// screen.
    ///
    /// Two things this can't be. It can't scroll one way: a form this long is
    /// scrolled *past* as often as it is scrolled to, so a loop that only
    /// swipes up can never come back to the name field — the element's own
    /// frame says which way to go. And "just hittable" isn't the target: a
    /// field resting at y=21 is hittable, and tapping it lands close enough to
    /// the status bar that focus doesn't take, which fails as an unrelated
    /// "neither element nor any descendant has keyboard focus". Aim for the
    /// band, not the edge.
    ///
    /// The drag is a measured press-and-move rather than `swipeUp()`, whose
    /// flick momentum overshoots by an amount no loop can predict.
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement, attempts: Int = 16) {
        guard element.waitForExistence(timeout: 10) else { return }
        let window = app.windows.firstMatch.frame
        let band = (top: window.minY + window.height * 0.24, bottom: window.minY + window.height * 0.60)

        for _ in 0..<attempts {
            let midY = element.frame.midY
            guard midY < band.top || midY > band.bottom else { return }
            drag(app, up: midY > band.bottom)
            // At a scroll limit — a tall field, or the end of the form — the
            // band is unreachable and every further drag is dead time.
            if element.frame.midY == midY { return }
        }
    }

    /// One controlled scroll step, about half the screen.
    private func drag(_ app: XCUIApplication, up: Bool) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.78 : 0.30))
        let to   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.30 : 0.78))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    /// `.textFields` / `.textViews` rather than `descendants(matching: .any)`:
    /// a `TextEditor` publishes more than one element carrying the identifier,
    /// and an untyped query then fails as ambiguous.
    private func fill(_ app: XCUIApplication, _ identifier: String, _ text: String,
                      multiline: Bool = false) {
        let field = multiline ? app.textViews[identifier] : app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(identifier) is not on the form")
        // `reveal` is help, not a precondition: XCUITest scrolls to a target
        // itself when it taps, and `isHittable` reports false for a field the
        // keyboard merely overlaps — which it can then still tap.
        reveal(app, field)
        field.tap()
        field.typeText(text)
    }

    /// The entry point: the retreat detail CTA acts, and a guest is asked to
    /// sign in before the form rather than after filling it.
    ///
    /// Worth its own test twice over. A control that silently does nothing is
    /// a failure mode this codebase has actually shipped (the
    /// `CircleIconButton` hit-testing note in CLAUDE.md), and the rest of the
    /// suite runs against `-preview-enquiry`, which would pass with the CTA
    /// wired to nothing at all. And the gate itself is load-bearing: the
    /// application's Email answer is the account's address, so an unsigned
    /// applicant has nothing to put there.
    func testRequestAPlaceAsksAGuestToSignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-preview-retreat"]
        app.launch()

        // Two of them: the cover CTA and the one closing the story. Either
        // should work; the cover's is the one on screen at rest.
        let cta = app.buttons["Request a place"].firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 30), "The retreat detail CTA never appeared")
        shot(app, "00-retreat-cta")
        cta.tap()

        // `-uitest-reset` leaves an anonymous guest, so the account sheet is
        // what should arrive — and the form should NOT, because eleven answers
        // written before being told to sign up is the worse order.
        XCTAssertTrue(app.buttons["account-close"].waitForExistence(timeout: 10),
                      "\"Request a place\" did not ask a guest to sign in")
        XCTAssertFalse(app.buttons["enquiry-submit"].exists,
                       "The application form opened without an account behind it")
        shot(app, "00-retreat-account-gate")
    }

    /// Every question the website asks, in the app, in the same words.
    func testTheFormAsksTheWebsiteQuestions() {
        let app = launch()

        let title = app.staticTexts["Request a place"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "The application form never appeared")
        shot(app, "01-enquiry-top")

        // A non-lazy `VStack` publishes every row whatever the scroll offset,
        // so existence here is a real check on the form's content and needs no
        // scrolling to make it one. Reaching the end of the form is proved once
        // at the bottom of this test rather than ten times over.
        let questions = [
            "Name",
            "Date of Birth",
            "Where are you based?",
            "Phone",
            "Instagram",
            "What retreat are you interested in attending?",
            "A little about you and why this retreat called you in.",
            "Where are you in your decision?",
            "Email",
            "Do you know a past member of Soulfull Gatherings? If so, who?"
        ]
        for question in questions {
            XCTAssertTrue(app.staticTexts[question].exists, "The form no longer asks: \(question)")
        }

        reveal(app, app.staticTexts["What retreat are you interested in attending?"])
        shot(app, "02-enquiry-middle")

        // Email is shown, not asked: no editable field, and the address on
        // screen is the account's. An editable one would be a control that
        // changes nothing — the server stamps the address from the JWT.
        XCTAssertFalse(app.textFields["enquiry-email"].exists,
                       "The email field is editable; it must be the account's address")
        let email = app.descendants(matching: .any)["enquiry-email"].firstMatch
        XCTAssertTrue(email.exists, "The Email question no longer shows an address")
        XCTAssertTrue(email.label.contains("hugo@soulfullgatherings.com"),
                      "Email shows \(email.label) rather than the signed-in account's address")

        // The investment question is long enough to be worth matching loosely.
        let investment = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "What's the investment")
        ).firstMatch
        XCTAssertTrue(investment.exists, "The form no longer asks about investment")

        // Its four bands are the answer list the retreat team groups by.
        for band in ["€3500+", "€4,500+", "€5,500+", "€6,500+"] {
            XCTAssertTrue(app.buttons[band].exists, "Investment band missing: \(band)")
        }
        let submit = app.buttons["enquiry-submit"]
        reveal(app, submit)
        XCTAssertTrue(submit.isHittable, "The form doesn't scroll through to Submit")
        shot(app, "03-enquiry-bottom")
    }

    /// Submit stays inert until every required question is answered, and says
    /// which ones are still open — then it actually goes somewhere.
    ///
    /// The send is a call to the `send-retreat-enquiry` Edge Function, so this
    /// asserts the form *settles*: either the thank-you panel or a failure it
    /// can explain. Both are passes. What would not be is a Submit that spins
    /// or silently does nothing, which is the regression worth catching — and
    /// the one a preview session (no permanent account, and the function may
    /// not be deployed yet) can still catch without a live send.
    func testSubmitWaitsForEveryRequiredAnswer() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Request a place"].waitForExistence(timeout: 20))

        let missing = app.staticTexts["enquiry-missing"]
        let submit = app.buttons["enquiry-submit"]
        reveal(app, submit)
        XCTAssertTrue(missing.exists, "An empty form should say what's still to answer")
        XCTAssertTrue(missing.label.contains("Date of Birth"), "Expected the unanswered date of birth to be listed")

        // Tapping Submit on an incomplete form must do nothing at all — no
        // composer, no alert, no half-built application leaving the device.
        submit.tap()
        XCTAssertTrue(missing.exists, "Submit acted on an incomplete application")

        // Answer everything. The two optional questions stay blank on purpose.
        fill(app, "enquiry-lastName", "De Santiago")

        let dob = app.buttons["enquiry-dob"]
        reveal(app, dob)
        dob.tap()   // opens the wheel already set to a valid, above-age date

        fill(app, "enquiry-basedIn", "Barcelona, Spain")
        fill(app, "enquiry-phone", "+34600000000")
        fill(app, "enquiry-about", "Two years of long hours and I want a week that puts me back in my body.", multiline: true)

        let decision = app.buttons["I'm completely ready to join"]
        reveal(app, decision)
        decision.tap()

        let band = app.buttons["€4,500+"]
        reveal(app, band)
        band.tap()

        shot(app, "03-enquiry-complete")
        XCTAssertFalse(missing.exists, "Every question is answered but Submit still reports gaps")

        reveal(app, submit)
        submit.tap()

        // One query matching either outcome — XCTest has no "wait for any of
        // these", and waiting on them in turn pays the full timeout whenever
        // the first one isn't what happened.
        let settled = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", ["enquiry-sent", "enquiry-error"])
        ).firstMatch
        XCTAssertTrue(settled.waitForExistence(timeout: 30),
                      "Submit neither sent the application nor said why it couldn't")
        shot(app, "04-enquiry-submitted")
    }
}
