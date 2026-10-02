import XCTest

final class LivingPageUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + arguments
        app.launch()
        return app
    }

    /// Menu items may surface as buttons or menuItems depending on presentation.
    private func menuItem(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let button = app.buttons[id]
        if button.exists { return button }
        return app.menuItems[id]
    }

    private func menuItemAppears(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 4) -> Bool {
        app.buttons[id].waitForExistence(timeout: timeout) || app.menuItems[id].waitForExistence(timeout: 1)
    }

    // MARK: - Baseline

    func testLaunchShowsBlankPrompt() {
        let app = launchApp()
        let status = app.staticTexts["status-line"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Status: Write a question.")
    }

    // MARK: - Answer ink completion (semantic element, not typed text)

    func testInjectedDrawingLeadsToConfirmationThenAnswerInk() {
        let app = launchApp(arguments: ["--inject-drawing"])

        let askKiro = app.buttons["ask-kiro"]
        XCTAssertTrue(askKiro.waitForExistence(timeout: 8), "confirmation slip did not appear")
        askKiro.tap()

        // The answer is real vector ink exposed to accessibility as a semantic
        // element labeled "Answer: …" — NOT a visible typed answer string.
        let answerInk = app.otherElements["answer-ink"]
        let answerInkAlt = app.staticTexts["answer-ink"]
        let appeared = answerInk.waitForExistence(timeout: 8) || answerInkAlt.waitForExistence(timeout: 2)
        XCTAssertTrue(appeared, "answer ink semantic element did not appear")

        // There must be NO visible typed answer element (removed proof view).
        XCTAssertFalse(app.staticTexts["answer-text"].exists, "typed answer should not exist")
    }

    // MARK: - Clear confirmation

    func testClearOnNonblankPageAsksForConfirmation() {
        let app = launchApp(arguments: ["--inject-drawing"])
        let askKiro = app.buttons["ask-kiro"]
        XCTAssertTrue(askKiro.waitForExistence(timeout: 8))

        app.buttons["clear"].tap()
        // Confirmation dialog appears for a nonblank page.
        let confirm = app.buttons["clear-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 4), "clear confirmation did not appear")
        confirm.tap()

        let status = app.staticTexts["status-line"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Status: Write a question.")
    }

    func testClearCancelKeepsPage() {
        let app = launchApp(arguments: ["--inject-drawing"])
        let askKiro = app.buttons["ask-kiro"]
        XCTAssertTrue(askKiro.waitForExistence(timeout: 8))

        app.buttons["clear"].tap()
        // On iPad the confirmation presents as a popover; the destructive
        // "Clear" is our button. Dismiss without clearing by tapping outside the
        // popover (the standard iPad cancel gesture), then verify nothing cleared.
        let confirm = app.buttons["clear-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 4), "confirmation did not appear")
        // Tap the status line (outside the popover) to cancel.
        app.staticTexts["status-line"].tap()

        let status = app.staticTexts["status-line"]
        XCTAssertTrue(status.waitForExistence(timeout: 6))
        XCTAssertNotEqual(status.label, "Status: Write a question.",
                          "dismissing without confirming must not clear the page; actual=\(status.label)")
    }

    // MARK: - Style selection

    func testStyleSelectionChangesLabel() {
        let app = launchApp()
        let picker = app.buttons["style-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        XCTAssertTrue(menuItemAppears(app, "style-quickSlanted"), "style menu did not open")
        menuItem(app, "style-quickSlanted").tap()

        // The picker label reflects the new selection.
        XCTAssertTrue(app.buttons["style-picker"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["style-picker"].label.contains("Slanted"))
    }

    func testPersonalWithoutProfileOffersFinishCalibration() {
        let app = launchApp()
        let picker = app.buttons["style-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        // With no profile seeded, Personal surfaces "Finish calibration".
        XCTAssertTrue(menuItemAppears(app, "style-personal-calibrate"), "Finish calibration option missing")
    }

    func testUsableProfileKeepsRefineCalibrationReachable() {
        // Seed a usable Personal profile; calibration must NOT be hidden.
        let app = launchApp(arguments: ["--seed-profile"])
        let picker = app.buttons["style-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        // A usable profile offers a native "Refine calibration" action AND the
        // selectable Personal hand; calibration stays user-reachable.
        XCTAssertTrue(menuItemAppears(app, "style-personal-refine"),
                      "Refine calibration must stay reachable once a profile exists")
        XCTAssertTrue(app.buttons["style-personal"].exists || app.menuItems["style-personal"].exists,
                      "Personal hand should be selectable")
        // The pre-calibration affordance is not shown once usable.
        XCTAssertFalse(app.buttons["style-personal-calibrate"].exists,
                       "Finish calibration should not show when a usable profile exists")
    }

    // MARK: - Calibration launch / resume / sample-save

    func testCalibrationLaunchAndAdvancePrompt() {
        let app = launchApp()
        let picker = app.buttons["style-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        XCTAssertTrue(menuItemAppears(app, "style-personal-calibrate"))
        menuItem(app, "style-personal-calibrate").tap()

        // Calibration sheet appears with a prompt and controls.
        let prompt = app.staticTexts["calibration-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "calibration prompt missing")
        XCTAssertTrue(app.buttons["calibration-save"].exists)
        XCTAssertTrue(app.buttons["calibration-clear"].exists)

        // Privacy copy is present (forbids signatures).
        XCTAssertTrue(app.staticTexts["calibration-privacy"].exists)

        // Next advances to a new prompt (navigation control works, resumable).
        let firstPrompt = prompt.label
        let next = app.buttons["calibration-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        XCTAssertNotEqual(prompt.label, firstPrompt, "Next did not advance the prompt")

        app.buttons["calibration-close"].tap()
    }

    // MARK: - Delete my handwriting (user-reachable privacy control)

    func testDeleteHandwritingIsReachableAndConfirms() {
        // Seed a usable Personal profile so the destructive control is offered.
        let app = launchApp(arguments: ["--seed-profile"])
        let picker = app.buttons["style-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        // With a profile present, the menu exposes "Delete my handwriting".
        XCTAssertTrue(menuItemAppears(app, "delete-handwriting"),
                      "delete-handwriting control missing from style menu")
        menuItem(app, "delete-handwriting").tap()

        // A destructive confirmation dialog appears; confirm the delete.
        let confirm = app.buttons["delete-handwriting-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 4),
                      "delete confirmation did not appear")
        confirm.tap()

        // After deletion the profile is gone: re-opening the menu now offers
        // "Finish calibration" and no longer offers the delete control.
        XCTAssertTrue(app.buttons["style-picker"].waitForExistence(timeout: 4))
        app.buttons["style-picker"].tap()
        XCTAssertTrue(menuItemAppears(app, "style-personal-calibrate"),
                      "Personal should require calibration after deletion")
        XCTAssertFalse(app.buttons["delete-handwriting"].exists,
                       "delete control should be gone after deletion")
    }
}
