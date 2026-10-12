//
//  PracticeCommentsTests.swift
//  SoulfullUITests
//
//  Comments under a practice (0032), as a member meets them: a movement page
//  ends with the newest two and a way into the rest; the sheet takes a comment,
//  turns down a link and says why; every comment of someone else's offers
//  Report (with a comment's reasons) and Block (asked first, then every comment
//  of theirs goes); your own offers Delete. A journal prompt has no comments.
//
//  Runs against `-preview-comments` (an in-memory conversation: nothing is
//  posted, reported or blocked on the server) over `-preview-instructors`,
//  which browses the live written libraries as a member. The server's half —
//  RLS, the filter, the thread view, the block — is verified live per 0032's
//  header.
//

import XCTest

@MainActor
final class PracticeCommentsTests: XCTestCase {

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
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-tab", "practice",
                               "-preview-instructors", "-preview-comments"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "comment-row")
    }

    private func row(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// The page's own rows, which stay in the tree under the sheet.
    private func previews(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "comment-preview")
    }

    private func preview(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        previews(app).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Scrolls until `element`'s centre — where `tap()` lands — sits above the
    /// docked bar (a card under it still reports hittable).
    private func scrollClearOfTheBar(_ element: XCUIElement, _ app: XCUIApplication) {
        let floor = app.windows.firstMatch.frame.maxY - 140
        var tries = 0
        while (!element.exists || !element.isHittable || element.frame.midY > floor) && tries < 12 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        XCTAssertTrue(element.isHittable && element.frame.midY <= floor,
                      "\(element) never scrolled clear of the tab bar")
    }

    /// Opens the "⋯" on a comment and picks one of its items.
    private func choose(_ item: String, on row: XCUIElement, in app: XCUIApplication) {
        let menu = row.descendants(matching: .any).matching(identifier: "comment-menu").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "No ⋯ on \(row.label)")
        menu.tap()
        let button = app.buttons[item]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The ⋯ menu offered no '\(item)'")
        button.tap()
    }

    private func openMovementPage(_ app: XCUIApplication) {
        let card = app.buttons["Movement"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "No Movement on the Practice landing")
        scrollClearOfTheBar(card, app)
        card.tap()
        let sequence = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Morning Mobility Flow")).firstMatch
        XCTAssertTrue(sequence.waitForExistence(timeout: 15), "The movement library never listed")
        sequence.tap()
        XCTAssertTrue(app.staticTexts["THE SEQUENCE"].waitForExistence(timeout: 10), "The movement page never opened")
    }

    func testAMovementPageShowsTheConversationAndTheSheetTakesAComment() {
        let app = launch()
        openMovementPage(app)

        // The foot of the page: the count, the newest two, a way into the rest.
        let heading = element(app, "comments-heading")
        let open = element(app, "comments-open")
        scrollClearOfTheBar(open, app)
        XCTAssertEqual(heading.label, "Comments, 3 comments")
        XCTAssertEqual(previews(app).count, 2, "The page shows the newest two")
        XCTAssertTrue(preview(app, startingWith: "Theo R.").exists)
        XCTAssertTrue(preview(app, startingWith: "Alma G., guide").exists, "A guide's comment says so")
        XCTAssertEqual(open.label, "Read all 3 comments")
        shot(app, "01-page-conversation")

        open.tap()
        let field = element(app, "comment-field")
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The comments sheet never opened")
        XCTAssertTrue(row(app, startingWith: "Nia K.").waitForExistence(timeout: 10), "The sheet shows every comment")
        XCTAssertEqual(rows(app).count, 3)
        let post = element(app, "comment-post")
        XCTAssertFalse(post.isEnabled, "An empty comment could be posted")
        shot(app, "02-sheet")

        // A link is turned down, and the words stay.
        field.tap()
        field.typeText("Found it here www.example.com")
        XCTAssertTrue(post.isEnabled)
        post.tap()
        let failure = element(app, "comment-failure")
        XCTAssertTrue(failure.waitForExistence(timeout: 10), "A comment with a link went through")
        XCTAssertTrue(failure.label.contains("links") || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'links'")).firstMatch.exists,
                      "The refusal should say links can't be posted")
        shot(app, "03-link-refused")

        // Rewritten, it posts and leads the list as "You".
        clear(field, app)
        field.typeText("Shoulders came down for the first time this week.")
        post.tap()
        let mine = row(app, startingWith: "You")
        XCTAssertTrue(mine.waitForExistence(timeout: 10), "The posted comment never appeared")
        XCTAssertTrue(failure.waitForNonExistence(timeout: 5), "The refusal stayed after a good post")
        XCTAssertEqual(rows(app).count, 4)
        XCTAssertTrue(rows(app).element(boundBy: 0).label.hasPrefix("You"), "Your comment should lead the list")
        shot(app, "04-posted")

        // Your own comment offers Delete, and asks first.
        choose("Delete comment", on: mine, in: app)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Delete went through without asking")
        delete.tap()
        XCTAssertTrue(mine.waitForNonExistence(timeout: 10), "The deleted comment stayed")
        XCTAssertEqual(rows(app).count, 3)

        element(app, "comments-close").tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertEqual(heading.label, "Comments, 3 comments", "The page and the sheet share one conversation")
        XCTAssertFalse(preview(app, startingWith: "You").exists, "The deleted comment stayed on the page")
    }

    func testACommentCanBeReportedAndItsAuthorBlocked() {
        let app = launch()
        openMovementPage(app)
        let open = element(app, "comments-open")
        scrollClearOfTheBar(open, app)
        open.tap()
        let theo = row(app, startingWith: "Theo R.")
        XCTAssertTrue(theo.waitForExistence(timeout: 10), "The sheet never showed Theo's comment")

        // Report: a comment's own reasons, and the comment quoted.
        choose("Report comment", on: theo, in: app)
        let send = element(app, "report-send")
        XCTAssertTrue(send.waitForExistence(timeout: 5), "The Report sheet never opened")
        XCTAssertTrue(app.staticTexts["Report this comment"].exists)
        XCTAssertTrue(element(app, "report-reason-offensive").exists, "A comment can be reported as offensive")
        XCTAssertFalse(element(app, "report-reason-photo").exists, "A photo isn't a reason to report a comment")
        XCTAssertFalse(send.isEnabled, "A report could be sent without a reason")
        shot(app, "05-report-comment")
        element(app, "report-reason-offensive").tap()
        send.tap()
        XCTAssertTrue(app.staticTexts["Thank you"].waitForExistence(timeout: 10), "The report never confirmed")
        element(app, "report-done").tap()
        XCTAssertTrue(send.waitForNonExistence(timeout: 5))

        // Block: asked first, then every comment of theirs goes.
        choose("Block Theo R.", on: theo, in: app)
        let confirm = app.buttons["Block"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Block went through without asking")
        shot(app, "06-block-confirm")
        confirm.tap()
        XCTAssertTrue(theo.waitForNonExistence(timeout: 10), "A blocked member's comment stayed")
        XCTAssertEqual(rows(app).count, 2)
        shot(app, "07-after-block")
    }

    func testAJournalPromptHasNoComments() {
        let app = launch()
        let card = app.buttons["Journal Prompts"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "No Journal Prompts on the Practice landing")
        scrollClearOfTheBar(card, app)
        card.tap()
        let prompt = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "?")).firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 15), "The journal never listed a prompt")
        prompt.tap()
        XCTAssertTrue(app.staticTexts["YOUR REFLECTION"].waitForExistence(timeout: 10), "The prompt never opened")

        for _ in 0..<3 { app.swipeUp(velocity: .slow) }
        XCTAssertFalse(element(app, "comments-heading").exists, "A journal prompt offered comments")
        XCTAssertFalse(element(app, "comments-open").exists)
        shot(app, "08-journal-without-comments")
    }

    /// Selects everything in a text field and deletes it.
    private func clear(_ field: XCUIElement, _ app: XCUIApplication) {
        field.tap()
        let text = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count + 4))
    }
}
