import XCTest

nonisolated final class TimelineDayPagingUITests: XCTestCase {
    @MainActor func testDateSelectionCarriesDraftWithoutChangingOriginal() {
        let app = TimelineUITestSupport.launch(
            arguments: ["--ui-testing-selected-draft", "--ui-testing-draft-at-1215"])
        let id = TimelineUITestSupport.draft(app).identifier
        let nextDate = TimelineUITestSupport.dayButton(app, offset: 1)
        // Adjacent weeks can expose date buttons that are still off screen.
        // XCTest can fail when it checks their hittability, so compare frames first.
        if nextDate.exists && app.frame.contains(nextDate.frame) {
            nextDate.tap()
        } else {
            TimelineUITestSupport.swipeTimeline(app, left: true)
        }
        XCTAssertTrue(
            TimelineUITestSupport.selectedDayButton(app, offset: 1).existsOrWait(timeout: 5))
        XCTAssertTrue(app.buttons[id].existsOrWait(timeout: 3))
        XCTAssertEqual(TimelineUITestSupport.time(app.buttons[id]), "12:15 PM")
        XCTAssertTrue(app.buttons["appointment-00000000-0000-0000-0000-00000000000C"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 3))
        XCTAssertEqual(TimelineUITestSupport.time(app.buttons[id]), "12:15 PM")
    }

    @MainActor func testTimelineSwipeChangesDayAndReturnsToOriginalAppointments() {
        // Keep normal motion on this check so animated paging commit paths remain covered.
        let app = TimelineUITestSupport.launch(arguments: ["--ui-testing-normal-motion"])
        let original = TimelineUITestSupport.original(app)
        let point = TimelineUITestSupport.coordinate(in: app, of: original, dx: 0.5, dy: 0.5)
        point.press(
            forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: -200, dy: 0)),
            withVelocity: .fast, thenHoldForDuration: 0)
        let next = app.buttons["appointment-00000000-0000-0000-0000-00000000000C"]
        XCTAssertTrue(
            TimelineUITestSupport.selectedDayButton(app, offset: 1).existsOrWait(timeout: 5))
        XCTAssertTrue(next.isHittable)
        XCTAssertFalse(app.textFields["Search patient by name"].exists)
        let back = TimelineUITestSupport.coordinate(in: app, of: next, dx: 0.3, dy: 0.5)
        back.press(
            forDuration: 0.05, thenDragTo: back.withOffset(CGVector(dx: 200, dy: 0)),
            withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(original.existsOrWait(timeout: 5))
        XCTAssertTrue(
            TimelineUITestSupport.selectedDayButton(app, offset: 0).existsOrWait(timeout: 5))
    }

    @MainActor func testTimelineSwipesAcrossWeekBoundaryAndEmptyDays() {
        let app = TimelineUITestSupport.launch(arguments: ["--ui-testing-week-boundary"])
        let calendar = TimelineUITestSupport.clinicCalendar
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? .now
        for offset in 1...2 {
            TimelineUITestSupport.swipeTimeline(app, left: true)
            XCTAssertTrue(
                TimelineUITestSupport.selectedDayButton(app, offset: offset, from: weekEnd)
                    .existsOrWait(timeout: 5))
        }
        for offset in [1, 0] {
            TimelineUITestSupport.swipeTimeline(app, left: false)
            XCTAssertTrue(
                TimelineUITestSupport.selectedDayButton(app, offset: offset, from: weekEnd)
                    .existsOrWait(timeout: 5))
        }
        XCTAssertTrue(TimelineUITestSupport.original(app).isHittable)
        XCTAssertFalse(TimelineUITestSupport.draft(app).exists)
    }

    @MainActor func testTimelineSwipeDuringSaveKeepsVisibleDay() {
        let app = TimelineUITestSupport.launch(
            arguments: ["--ui-testing-selected-draft", "--ui-testing-gated-save"])
        let id = TimelineUITestSupport.draft(app).identifier
        app.buttons["Done"].tap()
        let release = app.buttons["release-test-save"]
        XCTAssertTrue(release.hittableOrWait(timeout: 10))
        defer { if release.exists { release.tap() } }
        XCTAssertFalse(app.buttons["Add"].exists)
        TimelineUITestSupport.swipeTimeline(app, left: true)
        XCTAssertTrue(TimelineUITestSupport.selectedDayButton(app, offset: 0).exists)
        XCTAssertTrue(
            TimelineUITestSupport.original(app).isHittable,
            "The current day must remain visible while saving.")
        XCTAssertFalse(app.buttons["Add"].exists, "The save must still be pending after the swipe.")
        release.tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 10))
        XCTAssertTrue(app.buttons[id].isHittable)
    }

    @MainActor func testTimelineSwipeCarriesUnsavedDraft() {
        let app = TimelineUITestSupport.launch(
            arguments: ["--ui-testing-selected-draft", "--ui-testing-draft-at-1215"])
        let id = TimelineUITestSupport.draft(app).identifier
        TimelineUITestSupport.swipeTimeline(app, left: true)
        XCTAssertTrue(
            TimelineUITestSupport.selectedDayButton(app, offset: 1).existsOrWait(timeout: 5))
        XCTAssertEqual(TimelineUITestSupport.time(app.buttons[id]), "12:15 PM")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 3))
        XCTAssertTrue(app.buttons[id].isHittable)
        XCTAssertEqual(TimelineUITestSupport.time(app.buttons[id]), "12:15 PM")
        TimelineUITestSupport.swipeTimeline(app, left: false)
        XCTAssertTrue(
            TimelineUITestSupport.selectedDayButton(app, offset: 0).existsOrWait(timeout: 5))
        XCTAssertEqual(
            TimelineUITestSupport.time(TimelineUITestSupport.original(app)), "12:00 PM")
        // The saved card remains in the adjacent page's accessibility tree.
        XCTAssertFalse(app.frame.intersects(app.buttons[id].frame))
    }
}
