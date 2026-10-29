import XCTest

nonisolated final class TimelineAdjustmentUITests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-timeline-adjustment"]
        app.launch()
        XCTAssertTrue(original(app).waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func original(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["appointment-00000000-0000-0000-0000-00000000000A"]
    }

    @MainActor private func draft(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND NOT (identifier IN %@)", "appointment-",
                [
                    "appointment-00000000-0000-0000-0000-00000000000A",
                    "appointment-00000000-0000-0000-0000-00000000000B",
                    "appointment-00000000-0000-0000-0000-00000000000C",
                ])
        ).firstMatch
    }

    @MainActor private func time(_ card: XCUIElement) -> String {
        card.label.components(separatedBy: ",")[0]
            .replacingOccurrences(of: "\u{202f}", with: " ")
    }

    @MainActor private func selectPatient(_ app: XCUIApplication) {
        let search = app.textFields["Search patient by name"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("Test Patient")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Test Patient")).firstMatch
            .tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        XCTAssertFalse(search.exists)
    }

    @MainActor private func hold(_ card: XCUIElement, move: CGFloat = 0) {
        let point = card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        point.press(
            forDuration: 0.45, thenDragTo: point.withOffset(CGVector(dx: 0, dy: move)),
            withVelocity: .slow, thenHoldForDuration: 0)
    }

    @MainActor private func drag(_ card: XCUIElement, by points: CGFloat, dwell: TimeInterval = 0) {
        let point = card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        point.press(
            forDuration: 0.1, thenDragTo: point.withOffset(CGVector(dx: 0, dy: points)),
            withVelocity: .slow, thenHoldForDuration: dwell)
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testHoldOnAppointmentCreatesCenteredBookingAndDragsBeforePatientSelection() {
        let app = launch()
        let originalTime = time(original(app))
        hold(original(app), move: 17)
        selectPatient(app)
        XCTAssertEqual(time(draft(app)), "12:15 PM")
        XCTAssertEqual(draft(app).value as? String, "30 min")
        XCTAssertEqual(time(original(app)), originalTime)
        XCTAssertFalse(app.staticTexts["details-opened"].exists)
        let done = app.buttons["Done"]
        let cancel = app.buttons["Cancel"]
        XCTAssertGreaterThan(done.frame.minY, draft(app).frame.maxY)
        XCTAssertLessThanOrEqual(done.frame.minY - draft(app).frame.maxY, 8)
        XCTAssertEqual(done.frame.maxX, draft(app).frame.maxX, accuracy: 3)
        XCTAssertLessThan(cancel.frame.maxX, done.frame.minX)
        XCTAssertFalse(app.navigationBars.buttons["Done"].exists)
        attach(app, "Booking with glass card actions")
        let id = draft(app).identifier
        done.tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
        XCTAssertEqual(time(app.buttons[id]), "12:15 PM")
        XCTAssertFalse(app.otherElements["appointment-duration-handle"].exists)
    }

    @MainActor func testHoldOnUnavailableTimeCreatesBooking() {
        let app = launch()
        let block = app.buttons["unavailable-time-00000000-0000-0000-0000-000000000014"]
        XCTAssertTrue(block.exists)
        hold(block)
        selectPatient(app)
        XCTAssertEqual(time(draft(app)), "11:00 AM")
        XCTAssertEqual(draft(app).value as? String, "30 min")
        XCTAssertTrue(block.exists)
        XCTAssertFalse(app.textFields["Optional label"].exists)
    }

    @MainActor func testUnavailableTimeTapMovesResizesAndCancelRestoresStoredBlock() {
        let app = launch()
        let block = app.buttons["unavailable-time-00000000-0000-0000-0000-000000000014"]
        block.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["Optional label"].exists)
        XCTAssertTrue(app.buttons["Delete"].exists)
        XCTAssertGreaterThan(block.frame.width, 300)
        drag(block, by: 15)
        XCTAssertEqual(time(block), "11:15 AM")
        XCTAssertFalse(app.textFields["Optional label"].exists)
        let handle = app.otherElements["unavailable-time-duration-handle"]
        XCTAssertTrue(handle.exists)
        drag(handle, by: -100)
        XCTAssertEqual(time(block), "11:15 AM")
        XCTAssertEqual(block.value as? String, "15 min")
        attach(app, "Unavailable time with shared card controls")
        app.buttons["Cancel"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
        XCTAssertEqual(time(block), "11:00 AM")
        XCTAssertEqual(block.value as? String, "30 min")
    }

    @MainActor func testUnavailableTimeCreationLabelReturnsToDraftAndCanReopen() {
        let app = launch()
        app.buttons["Add"].tap()
        app.segmentedControls.buttons["Unavailable Time"].tap()
        let label = app.textFields["Optional label"]
        XCTAssertTrue(label.waitForExistence(timeout: 3))
        label.tap()
        label.typeText("Holiday")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        let block = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier != %@", "unavailable-time-",
                "unavailable-time-00000000-0000-0000-0000-000000000014")
        ).firstMatch
        XCTAssertEqual(block.value as? String, "30 min")
        XCTAssertFalse(app.buttons["Delete"].exists)
        drag(block, by: 15)
        let movedTime = time(block)
        XCTAssertFalse(label.exists)
        block.tap()
        XCTAssertTrue(label.waitForExistence(timeout: 3))
        XCTAssertEqual(label.value as? String, "Holiday")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        XCTAssertEqual(time(block), movedTime)
        let id = block.identifier
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
        XCTAssertEqual(time(app.buttons[id]), movedTime)
    }

    @MainActor func testUnavailableTimeDeleteConfirmsAtCard() {
        let app = launch()
        let block = app.buttons["unavailable-time-00000000-0000-0000-0000-000000000014"]
        block.tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        let delete = app.buttons["Delete"]
        XCTAssertGreaterThan(delete.frame.minY, block.frame.maxY)
        delete.tap()
        let confirm = app.buttons["Delete Unavailable Time"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertTrue(block.exists)
        attach(app, "Unavailable time delete confirmation")
        confirm.tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
        XCTAssertFalse(block.exists)
    }

    @MainActor func testHoldOnEmptyTimelineCreatesCenteredBooking() {
        let app = launch()
        let card = original(app)
        let point = card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: -120))
        point.press(forDuration: 0.45)
        selectPatient(app)
        XCTAssertEqual(time(draft(app)), "10:00 AM")
        XCTAssertEqual(draft(app).value as? String, "30 min")
    }

    @MainActor func testSelectedDraftCanMoveResizeAndCancel() {
        let app = launch()
        hold(original(app))
        selectPatient(app)
        drag(draft(app), by: 15)
        XCTAssertEqual(time(draft(app)), "12:15 PM")
        let handle = app.otherElements["appointment-duration-handle"]
        XCTAssertTrue(handle.exists)
        drag(handle, by: -100)
        XCTAssertEqual(time(draft(app)), "12:15 PM")
        XCTAssertEqual(draft(app).value as? String, "15 min")
        XCTAssertFalse(app.otherElements["appointment-start-handle"].exists)
        let id = draft(app).identifier
        app.buttons["Cancel"].tap()
        let discard = app.buttons["Discard Changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        attach(app, "Cancel confirmation anchored to card button")
        discard.tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons[id].exists)
        XCTAssertEqual(time(original(app)), "12:00 PM")
    }

    @MainActor func testHoldOverBreakExpandsAndMovingOutCollapses() {
        let app = launch()
        hold(original(app))
        selectPatient(app)
        let initialY = draft(app).frame.minY
        drag(draft(app), by: 76, dwell: 0.9)
        XCTAssertEqual(time(draft(app)), "2:30 PM")
        XCTAssertEqual(draft(app).frame.minY, initialY + 76, accuracy: 8)
        XCTAssertTrue(app.staticTexts["2\u{202f}PM"].exists)
        attach(app, "Expanded break")
        drag(draft(app), by: -110)
        XCTAssertEqual(time(draft(app)), "12:40 PM")
        XCTAssertFalse(app.staticTexts["2\u{202f}PM"].exists)
    }

    @MainActor func testDateSelectionCarriesDraftWithoutChangingOriginal() {
        let app = launch()
        hold(original(app), move: 17)
        selectPatient(app)
        let id = draft(app).identifier
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: 1, to: .now) else {
            XCTFail("The next date is missing.")
            return
        }
        let nextDate = app.buttons[
            next.formatted(.dateTime.weekday(.wide).month(.wide).day().year())]
        if nextDate.exists {
            nextDate.tap()
        } else {
            app.scrollViews.firstMatch.swipeLeft()
        }
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 3))
        XCTAssertEqual(time(app.buttons[id]), "12:15 PM")
        XCTAssertTrue(app.buttons["appointment-00000000-0000-0000-0000-00000000000C"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
        XCTAssertEqual(time(app.buttons[id]), "12:15 PM")
    }

    @MainActor func testAddButtonStillUsesPatientSelection() {
        let app = launch()
        app.buttons["Add"].tap()
        selectPatient(app)
        XCTAssertTrue(draft(app).exists)
        XCTAssertTrue(app.otherElements["appointment-duration-handle"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
    }

    @MainActor func testDoneWithoutPatientReopensSelection() {
        let app = launch()
        hold(original(app))
        let search = app.textFields["Search patient by name"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        app.buttons["Back"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        XCTAssertTrue(done.isEnabled)
        done.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Add"].exists)
    }

    @MainActor func testSharedSheetSwitchesFocusAndSwipeKeepsDraft() {
        let app = launch()
        app.buttons["Add"].tap()
        let search = app.textFields["Search patient by name"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        // Typing without a tap verifies that the visible field received focus.
        search.typeText("Temporary search")
        app.segmentedControls.buttons["Unavailable Time"].tap()
        let label = app.textFields["Optional label"]
        XCTAssertTrue(label.waitForExistence(timeout: 3))
        label.typeText("Travel")
        XCTAssertFalse(search.exists)
        app.segmentedControls.buttons["Appointment"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "Search patient by name")
        search.typeText("New search")
        app.segmentedControls.buttons["Unavailable Time"].tap()
        XCTAssertTrue(label.waitForExistence(timeout: 3))
        XCTAssertEqual(label.value as? String, "Optional label")
        label.typeText("Kept label")
        let bar = app.navigationBars["Unavailable Time"]
        let top = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        top.press(forDuration: 0.1, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 650)))
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        XCTAssertFalse(label.exists)
        let block = newBlock(app)
        XCTAssertTrue(block.exists)
        XCTAssertEqual(block.value as? String, "30 min")
        block.tap()
        XCTAssertTrue(label.waitForExistence(timeout: 3))
        XCTAssertEqual(label.value as? String, "Kept label")
        attach(app, "Shared creation sheet after swipe and reopen")
    }

    @MainActor func testHoldSwitchToUnavailableTimeKeepsFirstDrag() {
        let app = launch()
        hold(original(app), move: 17)
        XCTAssertTrue(
            app.segmentedControls.buttons["Unavailable Time"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["Unavailable Time"].tap()
        app.buttons["Continue"].tap()
        let block = newBlock(app)
        XCTAssertTrue(block.waitForExistence(timeout: 3))
        XCTAssertEqual(time(block), "12:15 PM")
        XCTAssertEqual(block.value as? String, "30 min")
        XCTAssertFalse(draft(app).exists)
        attach(app, "Hold draft after type switch")
    }

    @MainActor func testPatientCreationCancelKeepsSharedAppointmentSession() {
        let app = launch()
        app.buttons["Add"].tap()
        let search = app.textFields["Search patient by name"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("New patient")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Add new patient")).firstMatch
            .tap()
        XCTAssertTrue(app.navigationBars["New Patient"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.segmentedControls.buttons["Unavailable Time"].isHittable)
        app.buttons["Cancel"].tap()
        let keep = app.buttons["Discard Changes"]
        if keep.waitForExistence(timeout: 1) { keep.tap() }
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "New patient")
        XCTAssertTrue(app.segmentedControls.buttons["Appointment"].isSelected)
    }

    @MainActor private func newBlock(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier != %@", "unavailable-time-",
                "unavailable-time-00000000-0000-0000-0000-000000000014")
        ).firstMatch
    }
    @MainActor func testTapStillOpensDetails() {
        let app = launch()
        original(app).tap()
        XCTAssertTrue(app.staticTexts["details-opened"].waitForExistence(timeout: 3))
    }

    @MainActor func testQuickSwipeDoesNotStartBooking() {
        let app = launch()
        let point = original(app).coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        point.press(
            forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: -80)),
            withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertEqual(time(original(app)), "12:00 PM")
        XCTAssertFalse(app.staticTexts["details-opened"].exists)
        XCTAssertFalse(draft(app).exists)
        XCTAssertFalse(app.textFields["Search patient by name"].exists)
    }
}
