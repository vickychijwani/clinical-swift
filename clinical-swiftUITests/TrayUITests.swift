import XCTest

nonisolated final class TrayUITests: XCTestCase {
    private let appointmentID = "appointment-00000000-0000-0000-0000-00000000000A"

    @MainActor
    private func launchDetails(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["--ui-testing-appointment-completion", "--open-appointment-details"] + arguments
        app.launch()
        let bar = app.navigationBars["Appointment"]
        if arguments.contains("--ui-testing-normal-motion") {
            XCTAssertTrue(bar.stableFrameOrWait(timeout: 5))
        } else {
            XCTAssertTrue(bar.hittableOrWait(timeout: 5))
        }
        return app
    }

    @MainActor
    private func launchSchedule(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-appointment-completion"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons[appointmentID].hittableOrWait(timeout: 5))
        return app
    }

    @MainActor
    func testDetailsNavigationKeepsTheSameSurfaceAndHeight() {
        let app = launchDetails()
        let original = app.navigationBars["Appointment"].frame
        app.buttons["View Patient"].tap()
        XCTAssertTrue(app.navigationBars["Patient Details"].hittableOrWait(timeout: 3))
        XCTAssertEqual(app.navigationBars["Patient Details"].frame.minY, original.minY, accuracy: 1)
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Appointment"].hittableOrWait(timeout: 3))
        XCTAssertEqual(app.navigationBars["Appointment"].frame.minY, original.minY, accuracy: 1)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Appointment"].absentOrWait(timeout: 3))
    }

    @MainActor
    func testKeyboardKeepsCompletionActionsReachableAndBlocksOutsideDismissal() {
        let app = launchDetails()
        app.buttons["Complete"].tap()
        app.textFields["completion-amount"].tap()
        app.textFields["completion-amount"].typeText("1")
        XCTAssertTrue(app.keys["1"].hittableOrWait(timeout: 5))
        XCTAssertTrue(app.buttons["complete-appointment"].isHittable)
        XCTAssertLessThan(
            app.buttons["complete-appointment"].frame.maxY, app.keyboards.firstMatch.frame.minY)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.08)).tap()
        XCTAssertTrue(app.navigationBars["Complete Appointment"].exists)
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
        record(app, name: "completion-keyboard")
    }

    @MainActor
    func testPatientOptionalFieldsAreVisibleByDefaultAndFitWithoutScrolling() {
        let app = launchDetails()
        app.buttons["View Patient"].tap()
        app.buttons["Edit Patient"].tap()
        let bar = app.navigationBars["Edit Patient"]
        XCTAssertTrue(bar.hittableOrWait(timeout: 5))
        XCTAssertTrue(app.staticTexts["Optional details"].exists)
        XCTAssertFalse(app.buttons["Optional details"].exists)
        XCTAssertTrue(app.textFields["Name"].isHittable)
        XCTAssertTrue(app.textFields["Phone number"].isHittable)
        XCTAssertTrue(app.buttons["Date of birth, Add"].isHittable)
        XCTAssertTrue(app.buttons["Other"].isHittable)
        record(app, name: "patient-edit-optional-details-visible")
    }

    @MainActor
    func testPatientChildCancellationPreservesTheDraftAndDismissalBoundary() {
        let app = launchDetails()
        app.buttons["View Patient"].tap()
        app.buttons["Edit Patient"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.hittableOrWait(timeout: 5))
        name.tap()
        name.typeText(" Updated")
        // Wait for the remote keyboard to present and shift the tray before tapping the DOB row.
        _ = app.keyboards.firstMatch.existsOrWait(timeout: 2)
        let dob = app.buttons["Date of birth, Add"]
        XCTAssertTrue(dob.stableFrameOrWait(timeout: 3))
        dob.tap()
        XCTAssertTrue(app.navigationBars["Date of birth"].hittableOrWait(timeout: 3))
        XCTAssertFalse(app.navigationBars["Edit Patient"].isHittable)
        record(app, name: "patient-dob-child")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)).tap()
        XCTAssertTrue(name.hittableOrWait(timeout: 3))
        record(app, name: "patient-form-grouped-background")
        XCTAssertTrue((name.value as? String)?.contains("Updated") == true)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)).tap()
        XCTAssertTrue(name.exists)
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
        swipeHeader(app.navigationBars["Edit Patient"], in: app)
        XCTAssertTrue(name.exists)
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].hittableOrWait(timeout: 3))
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(name.absentOrWait(timeout: 3))
    }

    @MainActor
    func testBookingPatientCancelKeepsSearchAndSaveReturnsToTheTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-timeline-adjustment"]
        app.launch()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 5))
        app.buttons["Add"].tap()
        let search = app.textFields["Search patient by name"]
        XCTAssertTrue(search.hittableOrWait(timeout: 3))
        search.typeText("Tray Patient")
        let create = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Add new patient")
        ).firstMatch
        create.tap()
        XCTAssertTrue(app.navigationBars["New Patient"].hittableOrWait(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(search.hittableOrWait(timeout: 3))
        XCTAssertEqual(search.value as? String, "Tray Patient")
        create.tap()
        XCTAssertTrue(app.navigationBars["New Patient"].hittableOrWait(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["New Patient"].absentOrWait(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 3))
        XCTAssertFalse(search.exists)
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Tray Patient")
            ).firstMatch.exists)
    }

    @MainActor
    func testSettingsUsesTheTrayAndCloses() {
        let app = launchSchedule()
        triggerShake()
        XCTAssertTrue(app.navigationBars["Settings"].hittableOrWait(timeout: 3))
        XCTAssertTrue(app.otherElements["tray-surface"].exists)
        XCTAssertTrue(app.staticTexts["Patient data backups"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].absentOrWait(timeout: 3))
    }

    @MainActor
    func testBackupWarningButtonShowsAcrossTabsAndOpensSettings() {
        let app = launchSchedule()
        XCTAssertTrue(app.buttons["Settings"].hittableOrWait(timeout: 3))
        app.tabBars.buttons["Patients"].tap()
        XCTAssertTrue(app.navigationBars["Patients"].hittableOrWait(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Patients"].isSelected)
        XCTAssertTrue(app.buttons["Settings"].hittableOrWait(timeout: 3))
        record(app, name: "patients-native-tabs")
        app.tabBars.buttons["Payments"].tap()
        XCTAssertTrue(app.navigationBars["Payments"].hittableOrWait(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Payments"].isSelected)
        XCTAssertTrue(app.buttons["Settings"].hittableOrWait(timeout: 3))
        record(app, name: "payments-filter-bar")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].hittableOrWait(timeout: 3))
        XCTAssertTrue(app.otherElements["tray-surface"].exists)
        XCTAssertTrue(app.staticTexts["Patient data backups"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].absentOrWait(timeout: 3))
    }

    @MainActor
    private func triggerShake() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("in.bitehaus.clinical.ui-testing.shake" as CFString),
            nil,
            nil,
            true
        )
    }

    @MainActor
    func testMessageBlocksBothInteractiveDismissalActions() {
        let app = launchDetails()
        app.buttons["Send Appointment Confirmation"].tap()
        let bar = app.navigationBars["Send Message"]
        XCTAssertTrue(bar.hittableOrWait(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.15)).tap()
        XCTAssertTrue(bar.exists)
        swipeHeader(bar, in: app)
        XCTAssertTrue(bar.exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(bar.absentOrWait(timeout: 3))
    }

    @MainActor
    func testHeaderSwipeClosesCleanDetails() {
        let app = launchDetails()
        let bar = app.navigationBars["Appointment"]
        swipeHeader(bar, in: app)
        XCTAssertTrue(bar.absentOrWait(timeout: 3))
        XCTAssertTrue(app.buttons[appointmentID].isHittable)
    }

    @MainActor
    func testShortHeaderDragReturnsToTheSameHeight() {
        // Keep normal motion on this check so animated tray spring return remains covered.
        let app = launchDetails(["--ui-testing-normal-motion"])
        let bar = app.navigationBars["Appointment"]
        let original = bar.frame
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(
                dx: original.minX + original.width * 0.7,
                dy: original.minY + original.height * 0.1
            ))
        start.press(
            forDuration: 0.05,
            thenDragTo: start.withOffset(CGVector(dx: 0, dy: 30)),
            withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(bar.stableFrameOrWait(timeout: 3))
        XCTAssertEqual(bar.frame.minY, original.minY, accuracy: 1)
    }

    @MainActor
    func testOutsideTapClosesCleanDetailsAndDoesNotTapTheSchedule() {
        let app = launchDetails()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)).tap()
        XCTAssertTrue(app.navigationBars["Appointment"].absentOrWait(timeout: 3))
        XCTAssertTrue(app.buttons[appointmentID].isHittable)
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
    }

    @MainActor
    func testOutsideTapClosesDetailsAndDiscardsDraftDirectly() {
        let app = launchDetails()
        app.buttons["Complete"].tap()
        app.textFields["completion-amount"].typeText("1000")
        app.navigationBars.buttons["BackButton"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)).tap()
        XCTAssertTrue(app.navigationBars["Appointment"].absentOrWait(timeout: 3))
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
    }

    @MainActor
    func testContentScrollDoesNotDismissAndEditorHandoffWorks() {
        let app = launchDetails()
        app.buttons["View Patient"].tap()
        let bar = app.navigationBars["Patient Details"]
        XCTAssertTrue(bar.existsOrWait(timeout: 3))
        let content = app.scrollViews.containing(.button, identifier: "patient-" + appointmentID)
            .firstMatch
        content.swipeDown()
        XCTAssertTrue(bar.exists)
        app.buttons["Edit Patient"].tap()
        XCTAssertTrue(app.buttons["Cancel"].hittableOrWait(timeout: 5))
        XCTAssertFalse(bar.exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons[appointmentID].hittableOrWait(timeout: 3))
    }

    @MainActor
    private func swipeHeader(_ bar: XCUIElement, in app: XCUIApplication) {
        let start = TimelineUITestSupport.coordinate(in: app, of: bar, dx: 0.7, dy: 0.1)
        start.press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.95)))
    }

    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        TimelineUITestSupport.attach(app, name, to: self)
    }
}
