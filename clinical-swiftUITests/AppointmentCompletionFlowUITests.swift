import XCTest

nonisolated final class AppointmentCompletionFlowUITests: XCTestCase {
    @MainActor
    func testBackKeepsDraftAndRootCloseDiscardsDirectly() {
        let app = AppointmentCompletionUITestSupport.launch(fromSchedule: true)
        app.textFields["completion-amount"].typeText("1000")
        app.segmentedControls["completion-method"].buttons["Cash"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["Complete"].tap()
        XCTAssertEqual(app.textFields["completion-amount"].value as? String, "1000")
        XCTAssertTrue(app.segmentedControls["completion-method"].buttons["Cash"].isSelected)
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["Close"].tap()
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
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

    @MainActor
    func testCompletionToastBooksFollowUpOnNextBusinessDay() {
        let app = AppointmentCompletionUITestSupport.launch(fromSchedule: true)
        app.buttons["complete-appointment"].tap()
        XCTAssertTrue(app.navigationBars["Complete Appointment"].absentOrWait(timeout: 5))

        let toastAction = app.buttons["Book follow-up"]
        XCTAssertTrue(toastAction.hittableOrWait(timeout: 3))
        XCTAssertTrue(app.staticTexts["Completed"].exists)
        toastAction.tap()

        XCTAssertTrue(toastAction.absentOrWait(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 5))
        XCTAssertFalse(app.textFields["Search patient by name"].exists)

        let calendar = TimelineUITestSupport.clinicCalendar
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        let nextBusinessDay =
            calendar.component(.weekday, from: tomorrow) == 1
            ? calendar.date(byAdding: .day, value: 1, to: tomorrow)!
            : tomorrow
        let expectedTitle = nextBusinessDay.formatted(
            TimelineUITestSupport.clinicFormatStyle.weekday().month().day())
        XCTAssertTrue(app.navigationBars[expectedTitle].existsOrWait(timeout: 3))

        let draft = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier != %@", "appointment-",
                AppointmentCompletionUITestSupport.appointmentID)
        ).firstMatch
        XCTAssertTrue(draft.existsOrWait(timeout: 3))
        XCTAssertTrue(draft.label.contains("Test Patient"))
        XCTAssertEqual(TimelineUITestSupport.time(draft), "10:00 AM")

        let followUpID = draft.identifier
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 5))
        XCTAssertTrue(app.buttons[followUpID].existsOrWait(timeout: 3))
    }
}
