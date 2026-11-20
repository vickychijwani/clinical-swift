import XCTest

@MainActor
enum TimelineUITestSupport {
    static let clinicTimeZone = TimeZone(identifier: "Asia/Kolkata")!
    static let clinicLocale = Locale(identifier: "en_IN")
    static let clinicCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clinicTimeZone
        calendar.locale = clinicLocale
        return calendar
    }()
    static var clinicFormatStyle: Date.FormatStyle {
        Date.FormatStyle(locale: clinicLocale, calendar: clinicCalendar, timeZone: clinicTimeZone)
    }

    static func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TZ"] = "America/Los_Angeles"
        app.launchArguments = ["--ui-testing-timeline-adjustment"] + arguments
        app.launch()
        XCTAssertTrue(original(app).existsOrWait(timeout: 5))
        if arguments.contains("--ui-testing-selected-draft") {
            XCTAssertTrue(draft(app).hittableOrWait(timeout: 5))
            XCTAssertTrue(draft(app).label.contains("Test Patient"))
            XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 3))
            XCTAssertFalse(app.textFields["Search patient by name"].exists)
        }
        return app
    }

    static func original(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["appointment-00000000-0000-0000-0000-00000000000A"]
    }

    static func draft(_ app: XCUIApplication) -> XCUIElement {
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

    static func newBlock(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier != %@", "unavailable-time-",
                "unavailable-time-00000000-0000-0000-0000-000000000014")
        ).firstMatch
    }

    static func time(_ card: XCUIElement) -> String {
        card.label.components(separatedBy: ",")[0]
            .replacingOccurrences(of: "\u{202f}", with: " ")
    }

    static func selectPatient(_ app: XCUIApplication) {
        let search = app.textFields["Search patient by name"]
        XCTAssertTrue(search.hittableOrWait(timeout: 3))
        search.tap()
        search.typeText("Test Patient")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Test Patient")).firstMatch
            .tap()
        XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 3))
        XCTAssertFalse(search.exists)
    }

    static func emptySpaceAbove(_ card: XCUIElement) -> XCUICoordinate {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0))
            .withOffset(CGVector(dx: 0, dy: -5))
    }

    static func hold(_ point: XCUICoordinate, move: CGFloat) {
        // Leave time for the 0.3-second recognizer to run on a busy CI simulator before release.
        point.press(
            forDuration: 1, thenDragTo: point.withOffset(CGVector(dx: 0, dy: move)),
            withVelocity: .slow, thenHoldForDuration: 0)
    }

    static func drag(_ card: XCUIElement, by points: CGFloat, dwell: TimeInterval = 0) {
        let point = card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        point.press(
            forDuration: 0.1, thenDragTo: point.withOffset(CGVector(dx: 0, dy: points)),
            withVelocity: .slow, thenHoldForDuration: dwell)
    }

    static func attach(_ app: XCUIApplication, _ name: String, to testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    static func dayButton(_ app: XCUIApplication, offset: Int) -> XCUIElement {
        guard let date = clinicCalendar.date(byAdding: .day, value: offset, to: .now) else {
            preconditionFailure("The calendar must support day navigation.")
        }
        return app.buttons[
            date.formatted(clinicFormatStyle.weekday(.wide).month(.wide).day().year())]
    }

    static func swipeTimeline(_ app: XCUIApplication, left: Bool) {
        let timeline = app.scrollViews["schedule-day-pager"]
        let start = timeline.coordinate(
            withNormalizedOffset: CGVector(dx: left ? 0.8 : 0.2, dy: 0.6))
        let end = timeline.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.2 : 0.8, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }
}
