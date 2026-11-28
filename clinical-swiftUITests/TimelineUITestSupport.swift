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

    /// Resolves `element.frame` once and returns an app-anchored coordinate to avoid repeated element queries.
    static func coordinate(
        in app: XCUIApplication,
        of element: XCUIElement,
        dx: CGFloat = 0.5,
        dy: CGFloat = 0.5,
        offsetX: CGFloat = 0,
        offsetY: CGFloat = 0
    ) -> XCUICoordinate {
        let rect = element.frame
        return app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(
                dx: rect.minX + rect.width * dx + offsetX,
                dy: rect.minY + rect.height * dy + offsetY
            )
        )
    }

    static func emptySpaceAbove(_ card: XCUIElement, in app: XCUIApplication) -> XCUICoordinate {
        coordinate(in: app, of: card, dx: 0.4, dy: 0, offsetY: -5)
    }

    static func hold(_ point: XCUICoordinate, move: CGFloat) {
        // Leave margin above the 0.3-second recognizer on a busy CI simulator before release.
        point.press(
            forDuration: 0.45, thenDragTo: point.withOffset(CGVector(dx: 0, dy: move)),
            withVelocity: XCUIGestureVelocity(250), thenHoldForDuration: 0)
    }

    static func drag(
        _ card: XCUIElement,
        in app: XCUIApplication,
        by points: CGFloat,
        dwell: TimeInterval = 0
    ) {
        let point = coordinate(in: app, of: card, dx: 0.4, dy: 0.5)
        point.press(
            forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: points)),
            withVelocity: XCUIGestureVelocity(250), thenHoldForDuration: dwell)
    }

    static func attach(_ app: XCUIApplication, _ name: String, to testCase: XCTestCase) {
        guard ProcessInfo.processInfo.environment["CLINICAL_UI_TEST_ATTACHMENTS"] == "1" else {
            return
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    static func dayLabel(offset: Int, from baseDate: Date = .now) -> String {
        guard let date = clinicCalendar.date(byAdding: .day, value: offset, to: baseDate) else {
            preconditionFailure("The calendar must support day navigation.")
        }
        return date.formatted(clinicFormatStyle.weekday(.wide).month(.wide).day().year())
    }

    static func dayButton(
        _ app: XCUIApplication, offset: Int, from baseDate: Date = .now
    ) -> XCUIElement {
        app.buttons[dayLabel(offset: offset, from: baseDate)]
    }

    static func selectedDayButton(
        _ app: XCUIApplication, offset: Int, from baseDate: Date = .now
    ) -> XCUIElement {
        let label = dayLabel(offset: offset, from: baseDate)
        return app.buttons.matching(
            NSPredicate(format: "label == %@ AND value CONTAINS %@", label, "Selected")
        ).firstMatch
    }

    static func swipeTimeline(_ app: XCUIApplication, left: Bool) {
        // Use app-normalized coordinates directly so XCTest skips repeated ScrollView snapshots.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.8 : 0.2, dy: 0.6))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.2 : 0.8, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }
}
