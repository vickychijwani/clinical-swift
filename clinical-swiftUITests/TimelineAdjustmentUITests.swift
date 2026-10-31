import XCTest

nonisolated final class TimelineAdjustmentUITests: XCTestCase {
    @MainActor private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-timeline-adjustment"] + arguments
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
        // Leave time for the 0.3-second recognizer to run on a busy CI simulator before release.
        point.press(
            forDuration: 1, thenDragTo: point.withOffset(CGVector(dx: 0, dy: move)),
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
        point.press(forDuration: 1)
        selectPatient(app)
        XCTAssertEqual(time(draft(app)), "10:00 AM")
        XCTAssertEqual(draft(app).value as? String, "30 min")
    }

    @MainActor func testHoldNearClosingCreatesBooking() {
        let app = launch()
        // The compact break puts 8:45 PM 362 points below the noon card's center.
        let point = original(app).coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: 362))
        attach(app, "Timeline before bottom-edge hold")
        point.press(forDuration: 0.4)
        selectPatient(app)
        XCTAssertEqual(time(draft(app)), "8:30 PM")
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
        let nextDate = dayButton(app, offset: 1)
        // Adjacent weeks can expose date buttons that are still off screen.
        // XCTest can fail when it checks their hittability, so compare frames first.
        if app.frame.contains(nextDate.frame) {
            nextDate.tap()
        } else {
            swipeTimeline(app, left: true)
        }
        expectation(
            for: NSPredicate(format: "value CONTAINS %@", "Selected"), evaluatedWith: nextDate)
        waitForExpectations(timeout: 5)
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

    @MainActor func testPatientListSurvivesTypeChangesAndSheetReopening() {
        let app = launch()
        app.buttons["Add"].tap()
        let search = app.textFields["Search patient by name"]
        let patient = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Test Patient")
        ).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertTrue(patient.waitForExistence(timeout: 3))

        for _ in 0..<2 {
            search.typeText("No matching patient")
            XCTAssertFalse(patient.exists)
            app.segmentedControls.buttons["Unavailable Time"].tap()
            XCTAssertTrue(app.textFields["Optional label"].waitForExistence(timeout: 3))
            app.segmentedControls.buttons["Appointment"].tap()
            XCTAssertTrue(search.waitForExistence(timeout: 3))
            XCTAssertEqual(search.value as? String, "Search patient by name")
            XCTAssertTrue(patient.waitForExistence(timeout: 3))
        }

        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        draft(app).tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertTrue(patient.waitForExistence(timeout: 3))
        search.typeText("Test")
        XCTAssertTrue(patient.waitForExistence(timeout: 3))
        patient.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        XCTAssertTrue(draft(app).label.contains("Test Patient"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
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
        // The cancelled touch must not turn the next tap into a booking.
        original(app).tap()
        XCTAssertTrue(app.staticTexts["details-opened"].waitForExistence(timeout: 3))
    }

    @MainActor func testTimelineSwipeChangesDayAndReturnsToOriginalAppointments() {
        let app = launch()
        let point = original(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        point.press(
            forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: -200, dy: 0)),
            withVelocity: .fast, thenHoldForDuration: 0)
        let next = app.buttons["appointment-00000000-0000-0000-0000-00000000000C"]
        let nextDay = dayButton(app, offset: 1)
        let selected = NSPredicate(format: "value CONTAINS %@", "Selected")
        expectation(for: selected, evaluatedWith: nextDay)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(next.isHittable)
        XCTAssertFalse(app.textFields["Search patient by name"].exists)
        let back = next.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        back.press(
            forDuration: 0.05, thenDragTo: back.withOffset(CGVector(dx: 200, dy: 0)),
            withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(original(app).waitForExistence(timeout: 5))
        let today = dayButton(app, offset: 0)
        expectation(for: selected, evaluatedWith: today)
        waitForExpectations(timeout: 5)
    }

    @MainActor private func dayButton(_ app: XCUIApplication, offset: Int) -> XCUIElement {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: .now) else {
            preconditionFailure("The calendar must support day navigation.")
        }
        return app.buttons[date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())]
    }

    @MainActor private func swipeTimeline(_ app: XCUIApplication, left: Bool) {
        let timeline = app.scrollViews["schedule-day-pager"]
        let start = timeline.coordinate(
            withNormalizedOffset: CGVector(dx: left ? 0.8 : 0.2, dy: 0.6))
        let end = timeline.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.2 : 0.8, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    @MainActor func testTimelineSwipesAcrossWeekBoundaryAndEmptyDays() {
        let app = launch()
        let selected = NSPredicate(format: "value CONTAINS %@", "Selected")
        for offset in 1...7 {
            swipeTimeline(app, left: true)
            expectation(for: selected, evaluatedWith: dayButton(app, offset: offset))
            waitForExpectations(timeout: 5)
        }
        for offset in (0...6).reversed() {
            swipeTimeline(app, left: false)
            expectation(for: selected, evaluatedWith: dayButton(app, offset: offset))
            waitForExpectations(timeout: 5)
        }
        XCTAssertTrue(original(app).isHittable)
        XCTAssertFalse(draft(app).exists)
    }

    @MainActor func testTimelineSwipeDuringSaveKeepsVisibleDay() {
        let app = launch(arguments: ["--ui-testing-delayed-save"])
        hold(original(app))
        selectPatient(app)
        let id = draft(app).identifier
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["Add"].exists)
        swipeTimeline(app, left: true)
        XCTAssertTrue((dayButton(app, offset: 0).value as? String)?.contains("Selected") == true)
        XCTAssertTrue(original(app).isHittable, "The current day must remain visible while saving.")
        XCTAssertFalse(app.buttons["Add"].exists, "The save must still be pending after the swipe.")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[id].isHittable)
    }

    @MainActor func testTimelineSwipeCarriesUnsavedDraft() {
        let app = launch()
        hold(original(app), move: 17)
        selectPatient(app)
        let id = draft(app).identifier
        swipeTimeline(app, left: true)
        expectation(
            for: NSPredicate(format: "value CONTAINS %@", "Selected"),
            evaluatedWith: dayButton(app, offset: 1))
        waitForExpectations(timeout: 5)
        XCTAssertEqual(time(app.buttons[id]), "12:15 PM")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons[id].isHittable)
        XCTAssertEqual(time(app.buttons[id]), "12:15 PM")
        swipeTimeline(app, left: false)
        expectation(
            for: NSPredicate(format: "value CONTAINS %@", "Selected"),
            evaluatedWith: dayButton(app, offset: 0))
        waitForExpectations(timeout: 5)
        XCTAssertEqual(time(original(app)), "12:00 PM")
        // The saved card remains in the adjacent page's accessibility tree.
        XCTAssertFalse(app.frame.intersects(app.buttons[id].frame))
    }
}
