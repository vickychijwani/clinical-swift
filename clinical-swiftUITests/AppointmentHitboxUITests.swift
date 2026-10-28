import XCTest

nonisolated final class AppointmentHitboxUITests: XCTestCase {
    /// Verifies that a clipped long patient name cannot extend its appointment button's hitbox.
    ///
    /// The fixture places a long-name appointment on the left and a short-name appointment on the
    /// right inside a deliberately narrow timeline. The test first taps the right card to establish
    /// a known selection, then taps the empty strip beyond both visual card edges where the left
    /// name's unconstrained hitbox used to extend. The second tap must not change the selection.
    ///
    /// It's not enough to test with a tap on the right card because the right name's hitbox may be
    /// rendered above the left name's, which would not trigger the bug at all.
    @MainActor
    func testLongNameDoesNotStealTapFromRightAppointment() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-appointment-hitboxes"]
        app.launch()

        let selectionStatus = app.staticTexts["selection-status"]
        XCTAssertTrue(selectionStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(selectionStatus.label, "No appointment selected")

        let leftAppointment = app.buttons[
            "appointment-00000000-0000-0000-0000-000000000001"
        ]
        let rightAppointment = app.buttons[
            "appointment-00000000-0000-0000-0000-000000000002"
        ]
        XCTAssertTrue(leftAppointment.waitForExistence(timeout: 5))
        XCTAssertTrue(rightAppointment.waitForExistence(timeout: 5))

        rightAppointment.tap()
        XCTAssertEqual(selectionStatus.label, "Selected right appointment")

        let leakedHitboxX = rightAppointment.frame.maxX + 24
        XCTAssertLessThan(leakedHitboxX, app.frame.maxX)

        let appOrigin = app.coordinate(withNormalizedOffset: .zero)
        let leakedHitboxArea = appOrigin.withOffset(
            CGVector(
                dx: leakedHitboxX - app.frame.minX,
                dy: leftAppointment.frame.midY - app.frame.minY
            )
        )
        leakedHitboxArea.tap()

        // The tap is outside every card, so the previous right-card selection must remain.
        XCTAssertEqual(selectionStatus.label, "Selected right appointment")
    }
    @MainActor
    func testMixedThreeColumnCardsKeepSeparateTapAreas() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-appointment-hitboxes", "--ui-testing-mixed-hitboxes"]
        app.launch()
        let status = app.staticTexts["selection-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let appointment = app.buttons["appointment-00000000-0000-0000-0000-000000000001"]
        let middle = app.buttons["unavailable-time-00000000-0000-0000-0000-000000000001"]
        let right = app.buttons["unavailable-time-00000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(right.waitForExistence(timeout: 5))
        middle.tap()
        XCTAssertEqual(status.label, "Selected middle block")
        right.tap()
        XCTAssertEqual(status.label, "Selected right block")
        app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(
                dx: right.frame.maxX + 24 - app.frame.minX,
                dy: right.frame.midY - app.frame.minY
            )
        ).tap()
        XCTAssertEqual(status.label, "Selected right block")
        appointment.tap()
        XCTAssertEqual(status.label, "Selected left appointment")
    }
    @MainActor
    func testUnavailableTimeEditorKeepsDateSelectionAndConfirmsDiscard() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-timeline-adjustment"]
        app.launch()
        let action = app.buttons["Unavailable Time"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
        let label = app.textFields["Optional label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        label.typeText("Draft travel")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        XCTAssertFalse(label.exists)
        let draft = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier != %@", "unavailable-time-",
                "unavailable-time-00000000-0000-0000-0000-000000000014")
        ).firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        let draftID = draft.identifier
        let calendar = Calendar.current
        let offset = calendar.component(.weekday, from: .now) == 1 ? 1 : -1
        guard let alternateDate = calendar.date(byAdding: .day, value: offset, to: .now) else {
            XCTFail("The adjacent date is missing.")
            return
        }
        let dateButton = app.buttons[
            alternateDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year())]
        XCTAssertTrue(dateButton.exists)
        dateButton.tap()
        XCTAssertTrue((dateButton.value as? String)?.contains("Selected") == true)
        XCTAssertTrue(app.buttons[draftID].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        let discard = app.buttons["Discard Changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        if app.buttons["Keep Editing"].exists {
            app.buttons["Keep Editing"].tap()
        } else {
            // Native popovers use an outside-tap region for cancellation.
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }
        XCTAssertTrue((dateButton.value as? String)?.contains("Selected") == true)
        app.buttons[draftID].tap()
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertEqual(label.value as? String, "Draft travel")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Unavailable time editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[draftID].exists)
        XCTAssertTrue((dateButton.value as? String)?.contains("Selected") == true)
    }
}
