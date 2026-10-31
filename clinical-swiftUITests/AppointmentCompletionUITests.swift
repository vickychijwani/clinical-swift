import XCTest

nonisolated final class AppointmentCompletionUITests: XCTestCase {
    private let appointmentID = "appointment-00000000-0000-0000-0000-00000000000A"

    @MainActor
    private func launch(_ arguments: [String] = [], fromSchedule: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-appointment-completion"] + arguments
        if !fromSchedule { app.launchArguments.append("--completion-open-form") }
        app.launch()
        if fromSchedule {
            let appointment = app.buttons[appointmentID]
            XCTAssertTrue(appointment.hittableOrWait(timeout: 5))
            appointment.tap()
            XCTAssertTrue(app.buttons["Complete"].hittableOrWait(timeout: 5))
            app.buttons["Complete"].tap()
        }
        XCTAssertTrue(app.navigationBars["Complete Appointment"].existsOrWait(timeout: 5))
        return app
    }

    @MainActor
    private func swipeSheetDown(_ app: XCUIApplication) {
        let bar = app.navigationBars["Complete Appointment"]
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.1))
        start.press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.95)))
        XCTAssertTrue(bar.exists)
    }

    @MainActor
    private func replaceAmount(_ app: XCUIApplication, with text: String) {
        let field = app.textFields["completion-amount"]
        field.tap()
        field.press(forDuration: 1)
        if app.menuItems["Select All"].hittableOrWait(timeout: 1) {
            app.menuItems["Select All"].tap()
            field.typeText(text)
        } else {
            let oldText = field.value as? String ?? ""
            field.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldText.count) + text)
        }
    }

    @MainActor
    func testCompactNativeFormAndOneLineLabels() {
        let app = launch()
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
        swipeSheetDown(app)

        field.tap()
        field.typeText("100000")
        XCTAssertEqual(field.value as? String, "100000")
        XCTAssertEqual(action.label, "₹1,00,000 Paid · Complete Appointment")
        XCTAssertLessThanOrEqual(title.frame.height, singleLineHeight + 1)
        XCTAssertLessThanOrEqual(title.frame.maxX, action.frame.maxX)
        XCTAssertTrue(action.isHittable)
        swipeSheetDown(app)
        replaceAmount(app, with: "999999")
        XCTAssertEqual(field.value as? String, "999999")
        field.typeText("9")
        XCTAssertEqual(field.value as? String, "999999")
        XCTAssertFalse(app.staticTexts["Enter a valid whole-rupee amount."].exists)
        XCTAssertEqual(action.label, "₹9,99,999 Paid · Complete Appointment")
        XCTAssertLessThanOrEqual(title.frame.height, singleLineHeight + 1)
        XCTAssertLessThanOrEqual(title.frame.maxX, action.frame.maxX)
    }

    @MainActor
    func testBackKeepsDraftAndRootCloseConfirmsDiscard() {
        let app = launch(fromSchedule: true)
        app.textFields["completion-amount"].typeText("1000")
        app.segmentedControls["completion-method"].buttons["Cash"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["Complete"].tap()
        XCTAssertEqual(app.textFields["completion-amount"].value as? String, "1000")
        XCTAssertTrue(app.segmentedControls["completion-method"].buttons["Cash"].isSelected)
        app.navigationBars.buttons["BackButton"].tap()
        let detailsBar = app.navigationBars["Appointment"]
        detailsBar.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.1)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.95)))
        XCTAssertTrue(detailsBar.exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].hittableOrWait(timeout: 3))
        if app.buttons["Keep Editing"].exists {
            app.buttons["Keep Editing"].tap()
        } else {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }
        app.buttons["Complete"].tap()
        XCTAssertEqual(app.textFields["completion-amount"].value as? String, "1000")
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["Close"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.buttons[appointmentID].hittableOrWait(timeout: 3))
        app.buttons[appointmentID].tap()
        app.buttons["Complete"].tap()
        XCTAssertEqual(app.textFields["completion-amount"].value as? String, "0")
        XCTAssertTrue(
            app.segmentedControls["completion-method"].buttons.allElementsBoundByIndex.allSatisfy {
                !$0.isSelected
            })
    }

    @MainActor
    func testCleanDetailsCanDismissAfterBack() {
        let app = launch()
        app.navigationBars.buttons["BackButton"].tap()
        let detailsBar = app.navigationBars["Appointment"]
        detailsBar.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.1)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.95)))
        XCTAssertTrue(detailsBar.absentOrWait(timeout: 3))
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
        app.buttons[appointmentID].tap()
        app.buttons["Complete"].tap()
        XCTAssertEqual(app.textFields["completion-amount"].value as? String, "0")
    }

    @MainActor
    func testPatientHistoryReturnsToItsOriginAndCompletionClosesTheFlow() {
        let app = launch()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["View Patient"].tap()
        let historyAppointment = app.buttons["patient-" + appointmentID]
        XCTAssertTrue(historyAppointment.hittableOrWait(timeout: 3))
        historyAppointment.tap()
        app.buttons["Complete"].tap()
        app.textFields["completion-amount"].typeText("1000")
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Appointment"].exists)
        app.buttons["Complete"].tap()
        XCTAssertEqual(app.textFields["completion-amount"].value as? String, "1000")
        app.buttons["complete-appointment"].coordinate(
            withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)
        ).tap()
        XCTAssertTrue(app.navigationBars["Complete Appointment"].absentOrWait(timeout: 5))
        XCTAssertTrue(app.buttons[appointmentID].exists)
        app.buttons[appointmentID].tap()
        XCTAssertFalse(app.buttons["Complete"].exists)
    }

    @MainActor
    func testSaveFailureKeepsTheFormAndMethod() {
        let app = launch(["--completion-credit-conflict"])
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
        let app = launch(["--completion-unknown-patient", "--completion-gated-save"])
        XCTAssertTrue(app.staticTexts["For Unknown Patient"].exists)
        app.buttons["complete-appointment"].tap()
        let release = app.buttons["release-test-save"]
        XCTAssertTrue(release.hittableOrWait(timeout: 5))
        defer { if release.exists { release.tap() } }
        XCTAssertFalse(app.navigationBars.buttons["BackButton"].exists)
        XCTAssertFalse(app.textFields["completion-amount"].isEnabled)
        XCTAssertFalse(app.segmentedControls["completion-method"].isEnabled)
        XCTAssertFalse(app.buttons["complete-appointment"].isEnabled)
        swipeSheetDown(app)
        XCTAssertFalse(app.buttons["complete-appointment"].isEnabled)
        release.tap()
        XCTAssertTrue(app.navigationBars["Complete Appointment"].absentOrWait(timeout: 5))
        XCTAssertTrue(app.buttons[appointmentID].exists)
    }
}
