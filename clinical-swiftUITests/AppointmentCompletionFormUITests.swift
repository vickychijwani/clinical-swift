import XCTest

nonisolated final class AppointmentCompletionFormUITests: XCTestCase {
    @MainActor
    func testCompactNativeFormAndOneLineLabels() {
        let app = AppointmentCompletionUITestSupport.launch()
        XCTAssertTrue(app.staticTexts["For Test Patient"].exists)
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        let field = app.textFields["completion-amount"]
        XCTAssertEqual(field.placeholderValue, "0")
        let methods = app.segmentedControls["completion-method"]
        XCTAssertTrue(field.isHittable)
        XCTAssertTrue(methods.isHittable)
        XCTAssertEqual(
            methods.buttons.allElementsBoundByIndex.map(\.label), ["UPI", "Cash", "Card", "Other"])
        XCTAssertTrue(methods.buttons.allElementsBoundByIndex.allSatisfy { !$0.isSelected })
        let action = app.buttons["complete-appointment"]
        XCTAssertEqual(action.label, "No Dues · Complete Appointment")
        let title = app.staticTexts["completion-action-title"]
        let singleLineHeight = title.frame.height
        XCTAssertTrue(action.isHittable)
        XCTAssertGreaterThan(action.frame.width, app.frame.width * 0.8)
        XCTAssertTrue(app.keyboards.firstMatch.existsOrWait(timeout: 3))
        XCTAssertFalse(app.keyboards.buttons["."].exists)
        XCTAssertLessThan(action.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertLessThan(
            app.keyboards.firstMatch.frame.minY
                - app.navigationBars["Complete Appointment"].frame.minY, 450)
        AppointmentCompletionUITestSupport.swipeSheetDown(app)

        field.tap()
        field.typeText("100000")
        XCTAssertEqual(field.value as? String, "100000")
        XCTAssertEqual(action.label, "₹1,00,000 Paid · Complete Appointment")
        XCTAssertLessThanOrEqual(title.frame.height, singleLineHeight + 1)
        XCTAssertLessThanOrEqual(title.frame.maxX, action.frame.maxX)
        XCTAssertTrue(action.isHittable)
        AppointmentCompletionUITestSupport.swipeSheetDown(app)
        AppointmentCompletionUITestSupport.replaceAmount(app, with: "999999")
        XCTAssertEqual(field.value as? String, "999999")
        field.typeText("9")
        XCTAssertEqual(field.value as? String, "999999")
        XCTAssertFalse(app.staticTexts["Enter a valid whole-rupee amount."].exists)
        XCTAssertEqual(action.label, "₹9,99,999 Paid · Complete Appointment")
        XCTAssertLessThanOrEqual(title.frame.height, singleLineHeight + 1)
        XCTAssertLessThanOrEqual(title.frame.maxX, action.frame.maxX)
    }

    @MainActor
    func testSaveFailureKeepsTheFormAndMethod() {
        let app = AppointmentCompletionUITestSupport.launch(["--completion-credit-conflict"])
        app.textFields["completion-amount"].typeText("1000")
        app.segmentedControls["completion-method"].buttons["Card"].tap()
        app.buttons["complete-appointment"].tap()
        XCTAssertTrue(app.alerts["Unable to complete appointment"].existsOrWait(timeout: 5))
        XCTAssertTrue(
            app.alerts.staticTexts[
                "This change would leave the patient with a credit balance. Check the earlier receipts."
            ].exists)
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(app.textFields["completion-amount"].value as? String, "1000")
        XCTAssertTrue(app.segmentedControls["completion-method"].buttons["Card"].isSelected)
        XCTAssertTrue(app.buttons["complete-appointment"].isEnabled)
        XCTAssertTrue(app.navigationBars.buttons["BackButton"].exists)
    }

    @MainActor
    func testUnknownPatientAndSavingControls() {
        let app = AppointmentCompletionUITestSupport.launch([
            "--completion-unknown-patient", "--completion-gated-save",
        ])
        XCTAssertTrue(app.staticTexts["For Unknown Patient"].exists)
        app.buttons["complete-appointment"].tap()
        let release = app.buttons["release-test-save"]
        XCTAssertTrue(release.hittableOrWait(timeout: 5))
        defer { if release.exists { release.tap() } }
        XCTAssertFalse(app.navigationBars.buttons["BackButton"].exists)
        XCTAssertFalse(app.textFields["completion-amount"].isEnabled)
        XCTAssertFalse(app.segmentedControls["completion-method"].isEnabled)
        XCTAssertFalse(app.buttons["complete-appointment"].isEnabled)
        AppointmentCompletionUITestSupport.swipeSheetDown(app)
        XCTAssertFalse(app.buttons["complete-appointment"].isEnabled)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)).tap()
        XCTAssertTrue(app.navigationBars["Complete Appointment"].exists)
        release.tap()
        XCTAssertTrue(app.navigationBars["Complete Appointment"].absentOrWait(timeout: 5))
        XCTAssertTrue(app.buttons[AppointmentCompletionUITestSupport.appointmentID].exists)
    }
}
