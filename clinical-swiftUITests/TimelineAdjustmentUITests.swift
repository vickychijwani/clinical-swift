import XCTest

nonisolated final class TimelineAdjustmentUITests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-timeline-adjustment"]
        app.launch()
        XCTAssertTrue(card(app).waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func card(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["appointment-00000000-0000-0000-0000-00000000000A"]
    }

    @MainActor private func savedTime(_ app: XCUIApplication) -> String {
        let appointment = card(app)
        let time = appointment.label.components(separatedBy: ",")[0]
        return "\(time) · \(appointment.value as? String ?? "")"
            .replacingOccurrences(of: "\u{202f}", with: " ")
    }

    @MainActor private func move(_ app: XCUIApplication, by points: CGFloat, hold: TimeInterval = 0)
    {
        let start = card(app).coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        start.press(
            forDuration: 0.45, thenDragTo: start.withOffset(CGVector(dx: 0, dy: points)),
            withVelocity: .slow, thenHoldForDuration: hold)
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testMoveSnapsWithoutOpeningDetails() {
        let app = launch()
        move(app, by: 17)
        XCTAssertEqual(savedTime(app), "12:15 PM · 30 min")
        XCTAssertFalse(app.staticTexts["details-opened"].exists)
        attach(app, "Moved appointment")
    }

    @MainActor func testHoldOverBreakExpandsAndMovingOutCollapses() {
        let app = launch()
        let originalY = card(app).frame.minY
        move(app, by: 76, hold: 0.9)
        XCTAssertEqual(savedTime(app), "2:30 PM · 30 min")
        XCTAssertEqual(card(app).frame.minY, originalY + 76, accuracy: 8)
        XCTAssertTrue(app.staticTexts["2\u{202f}PM"].exists)
        attach(app, "Expanded break")
        let expandedY = card(app).frame.minY
        move(app, by: -110)
        XCTAssertEqual(savedTime(app), "12:40 PM · 30 min")
        XCTAssertEqual(card(app).frame.minY, expandedY - 110, accuracy: 8)
        XCTAssertFalse(app.staticTexts["2\u{202f}PM"].exists)
        attach(app, "Collapsed break after exit")
    }

    @MainActor func testPassingBreakKeepsItCompact() {
        let app = launch()
        move(app, by: 112)
        XCTAssertEqual(savedTime(app), "4:20 PM · 30 min")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "• BREAK")).firstMatch
                .exists)
        attach(app, "Passed the compact break")
    }

    @MainActor func testResizeFromBothHandles() {
        let app = launch()
        card(app).press(forDuration: 0.45)
        XCTAssertFalse(app.staticTexts["details-opened"].exists)
        let end = app.otherElements["appointment-end-handle"]
        XCTAssertTrue(end.waitForExistence(timeout: 3))
        let endPoint = end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        endPoint.press(forDuration: 0.1, thenDragTo: endPoint.withOffset(CGVector(dx: 0, dy: 17)))
        XCTAssertEqual(savedTime(app), "12:00 PM · 45 min")
        let start = app.otherElements["appointment-start-handle"]
        let startPoint = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        startPoint.press(
            forDuration: 0.1, thenDragTo: startPoint.withOffset(CGVector(dx: 0, dy: 10)))
        XCTAssertEqual(savedTime(app), "12:10 PM · 35 min")
        attach(app, "Resized appointment")
    }

    @MainActor func testTapStillOpensDetails() {
        let app = launch()
        card(app).tap()
        XCTAssertTrue(app.staticTexts["details-opened"].waitForExistence(timeout: 3))
    }

    @MainActor func testQuickSwipeDoesNotChangeTime() {
        let app = launch()
        let point = card(app).coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        point.press(
            forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: -80)),
            withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertEqual(savedTime(app), "12:00 PM · 30 min")
        XCTAssertFalse(app.staticTexts["details-opened"].exists)
    }

    @MainActor func testAdjustmentModeUsesFullWidthAndDoneRestoresControls() {
        let app = launch()
        let originalWidth = card(app).frame.width
        card(app).press(forDuration: 0.45)
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(card(app).frame.width, originalWidth * 1.8)
        XCTAssertFalse(app.buttons["Settings"].exists)
        XCTAssertFalse(app.buttons["Add"].exists)
        XCTAssertFalse(app.buttons["Unavailable Time"].exists)
        XCTAssertFalse(app.tabBars.buttons["Patients"].exists)
        card(app).tap()
        let other = app.buttons["appointment-00000000-0000-0000-0000-00000000000B"]
        other.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertFalse(app.staticTexts["details-opened"].exists)
        attach(app, "Translucent full-width adjustment")
        done.tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Patients"].exists)
        XCTAssertFalse(app.otherElements["appointment-end-handle"].exists)
        XCTAssertEqual(card(app).frame.width, originalWidth, accuracy: 1)
    }

    @MainActor func testDateSelectionCarriesTimeAndDurationAcrossConflicts() {
        let app = launch()
        move(app, by: 17)
        let originalTime = savedTime(app)
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
        XCTAssertTrue(card(app).waitForExistence(timeout: 3))
        XCTAssertEqual(savedTime(app), originalTime)
        XCTAssertTrue(app.buttons["Done"].exists)
        XCTAssertTrue(app.buttons["appointment-00000000-0000-0000-0000-00000000000C"].exists)
        attach(app, "Adjustment carried to next day")
        app.buttons["Done"].tap()
        XCTAssertEqual(savedTime(app), originalTime)
        XCTAssertFalse(app.otherElements["appointment-end-handle"].exists)
    }

}
