import XCTest

nonisolated final class TimelineBookingHoldUITests: XCTestCase {
    @MainActor func testHoldAboveAppointmentCanDragIntoAnOverlap() {
        let app = TimelineUITestSupport.launch()
        let original = TimelineUITestSupport.original(app)
        let originalTime = TimelineUITestSupport.time(original)
        TimelineUITestSupport.hold(TimelineUITestSupport.emptySpaceAbove(original), move: 30)
        TimelineUITestSupport.selectPatient(app)
        let draft = TimelineUITestSupport.draft(app)
        XCTAssertEqual(TimelineUITestSupport.time(draft), "12:15 PM")
        XCTAssertEqual(draft.value as? String, "30 min")
        XCTAssertEqual(TimelineUITestSupport.time(original), originalTime)
        XCTAssertFalse(app.staticTexts["details-opened"].exists)
        let done = app.buttons["Done"]
        let cancel = app.buttons["Cancel"]
        XCTAssertGreaterThan(done.frame.minY, draft.frame.maxY)
        XCTAssertLessThanOrEqual(done.frame.minY - draft.frame.maxY, 8)
        XCTAssertEqual(done.frame.maxX, draft.frame.maxX, accuracy: 3)
        XCTAssertLessThan(cancel.frame.maxX, done.frame.minX)
        XCTAssertFalse(app.navigationBars.buttons["Done"].exists)
        TimelineUITestSupport.attach(app, "Booking with glass card actions", to: self)
        let id = draft.identifier
        done.tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 3))
        XCTAssertEqual(TimelineUITestSupport.time(app.buttons[id]), "12:15 PM")
        XCTAssertFalse(app.otherElements["appointment-duration-handle"].exists)
    }

    @MainActor func testHoldAndDragOnAppointmentMovesTheSameCard() {
        let app = TimelineUITestSupport.launch()
        let card = TimelineUITestSupport.original(app)
        TimelineUITestSupport.hold(
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)), move: 17)
        XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 3))
        XCTAssertEqual(TimelineUITestSupport.time(card), "12:15 PM")
        XCTAssertEqual(card.value as? String, "30 min")
        XCTAssertTrue(card.label.contains("Test Patient"))
        XCTAssertFalse(app.staticTexts["details-opened"].exists)
        XCTAssertFalse(app.textFields["Search patient by name"].exists)
        XCTAssertFalse(TimelineUITestSupport.draft(app).exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 3))
        XCTAssertEqual(TimelineUITestSupport.time(card), "12:15 PM")
    }

    @MainActor func testHoldOnEmptyTimelineCreatesCenteredBooking() {
        let app = TimelineUITestSupport.launch()
        let card = TimelineUITestSupport.original(app)
        let point = card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: -120))
        point.press(forDuration: 1)
        TimelineUITestSupport.selectPatient(app)
        let draft = TimelineUITestSupport.draft(app)
        XCTAssertEqual(TimelineUITestSupport.time(draft), "10:00 AM")
        XCTAssertEqual(draft.value as? String, "30 min")
    }

    @MainActor func testHoldNearClosingCreatesBooking() {
        let app = TimelineUITestSupport.launch()
        // The compact break puts 8:45 PM 362 points below the noon card's center.
        let point = TimelineUITestSupport.original(app)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: 362))
        TimelineUITestSupport.attach(app, "Timeline before bottom-edge hold", to: self)
        point.press(forDuration: 0.4)
        TimelineUITestSupport.selectPatient(app)
        let draft = TimelineUITestSupport.draft(app)
        XCTAssertEqual(TimelineUITestSupport.time(draft), "8:30 PM")
        XCTAssertEqual(draft.value as? String, "30 min")
    }

    @MainActor func testAddButtonStillUsesPatientSelection() {
        let app = TimelineUITestSupport.launch()
        app.buttons["Add"].tap()
        TimelineUITestSupport.selectPatient(app)
        XCTAssertTrue(TimelineUITestSupport.draft(app).exists)
        XCTAssertTrue(app.otherElements["appointment-duration-handle"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 3))
    }

    @MainActor func testTapStillOpensDetails() {
        let app = TimelineUITestSupport.launch()
        TimelineUITestSupport.original(app).tap()
        XCTAssertTrue(app.staticTexts["details-opened"].existsOrWait(timeout: 3))
    }

    @MainActor func testQuickSwipeDoesNotStartBooking() {
        let app = TimelineUITestSupport.launch()
        let original = TimelineUITestSupport.original(app)
        let point = original.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        point.press(
            forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: -80)),
            withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertEqual(TimelineUITestSupport.time(original), "12:00 PM")
        XCTAssertFalse(app.staticTexts["details-opened"].exists)
        XCTAssertFalse(TimelineUITestSupport.draft(app).exists)
        XCTAssertFalse(app.textFields["Search patient by name"].exists)
        // The cancelled touch must not turn the next tap into a booking.
        original.tap()
        XCTAssertTrue(app.staticTexts["details-opened"].existsOrWait(timeout: 3))
    }
}
