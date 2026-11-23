import XCTest

@MainActor
enum AppointmentCompletionUITestSupport {
    static let appointmentID = "appointment-00000000-0000-0000-0000-00000000000A"

    static func launch(_ arguments: [String] = [], fromSchedule: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TZ"] = "America/Los_Angeles"
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
        // Wait for the initial amount-field keyboard so an immediate Back tap does not interrupt
        // keyboard presentation and leave XCUITest's animation-idle tracker stuck.
        if !app.keyboards.firstMatch.existsOrWait(timeout: 5) {
            // On a cold CI simulator clone, InputUI can drop its first remote keyboard connection
            // before startup finishes; tapping the amount field once reconnects it.
            let field = app.textFields["completion-amount"]
            XCTAssertTrue(field.hittableOrWait(timeout: 5))
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.existsOrWait(timeout: 5))
        }
        return app
    }

    static func swipeSheetDown(_ app: XCUIApplication) {
        let bar = app.navigationBars["Complete Appointment"]
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.1))
        start.press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.95)))
        XCTAssertTrue(bar.exists)
    }

    static func replaceAmount(_ app: XCUIApplication, with text: String) {
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
}
