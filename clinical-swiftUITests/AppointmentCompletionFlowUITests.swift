import XCTest

nonisolated final class AppointmentCompletionFlowUITests: XCTestCase {
    @MainActor
    func testBackKeepsDraftAndRootCloseConfirmsDiscard() {
        let app = AppointmentCompletionUITestSupport.launch(fromSchedule: true)
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
        XCTAssertTrue(app.buttons["Discard Changes"].hittableOrWait(timeout: 3))
        if app.buttons["Keep Editing"].exists {
            app.buttons["Keep Editing"].tap()
        } else {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }
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
        let appointment = app.buttons[AppointmentCompletionUITestSupport.appointmentID]
        XCTAssertTrue(appointment.hittableOrWait(timeout: 3))
        appointment.tap()
        app.buttons["Complete"].tap()
        XCTAssertEqual(app.textFields["completion-amount"].value as? String, "0")
        XCTAssertTrue(
            app.segmentedControls["completion-method"].buttons.allElementsBoundByIndex.allSatisfy {
                !$0.isSelected
            })
    }

    @MainActor
    func testCleanDetailsCanDismissAfterBack() {
        let app = AppointmentCompletionUITestSupport.launch()
        app.navigationBars.buttons["BackButton"].tap()
        let detailsBar = app.navigationBars["Appointment"]
        detailsBar.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.1)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.95)))
        XCTAssertTrue(detailsBar.absentOrWait(timeout: 3))
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
        app.buttons[AppointmentCompletionUITestSupport.appointmentID].tap()
        app.buttons["Complete"].tap()
        XCTAssertEqual(app.textFields["completion-amount"].value as? String, "0")
    }

    @MainActor
    func testPatientHistoryReturnsToItsOriginAndCompletionClosesTheFlow() {
        let app = AppointmentCompletionUITestSupport.launch()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["View Patient"].tap()
        let historyAppointment =
            app.buttons["patient-" + AppointmentCompletionUITestSupport.appointmentID]
        XCTAssertTrue(historyAppointment.hittableOrWait(timeout: 3))
        historyAppointment.tap()
        app.buttons["Complete"].tap()
        app.textFields["completion-amount"].typeText("1000")
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Appointment"].exists)
        app.buttons["Complete"].tap()
        XCTAssertEqual(app.textFields["completion-amount"].value as? String, "1000")
        app.buttons["complete-appointment"].tap()
        XCTAssertTrue(app.navigationBars["Complete Appointment"].absentOrWait(timeout: 5))
        let appointment = app.buttons[AppointmentCompletionUITestSupport.appointmentID]
        XCTAssertTrue(appointment.exists)
        appointment.tap()
        XCTAssertFalse(app.buttons["Complete"].exists)
    }
}
