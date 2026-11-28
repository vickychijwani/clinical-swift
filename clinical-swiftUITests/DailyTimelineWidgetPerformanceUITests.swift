import XCTest

nonisolated final class DailyTimelineWidgetPerformanceUITests: XCTestCase {
    private enum HeaderElementKind: String {
        case button
        case link
        case staticText
        case any
    }

    private struct TapMeasurement {
        let label: String
        let totalMS: Int
        let afterTapMS: Int
        let timedOut: Bool
    }

    @MainActor
    func testDailyTimelineWidgetButtonLatency() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            env["CLINICAL_WIDGET_PERF_TEST"] == "1",
            "Set TEST_RUNNER_CLINICAL_WIDGET_PERF_TEST=1 on a prepared simulator or run make widget-perf-test on a physical device."
        )
        continueAfterFailure = true
        #if targetEnvironment(simulator)
            // Idle Simulator Debug renders ~55–70ms after tap, and up to ~600ms under 5-clone
            // parallel CI load (~435–1150ms total), vs 7–15s on regression.
            let defaultMaxLatencyMS = 1000
            let defaultMaxTotalMS = 2000
            prepareSimulatorWidgetEnvironment()
            defer { cleanupSimulatorWidgetEnvironment() }
        #else
            // Physical Release taps complete in ~160–285ms after tap (~880–980ms total) vs 2.1–6.4s on regression.
            let defaultMaxLatencyMS = 350
            let defaultMaxTotalMS = 1200
        #endif

        let maxLatencyMS = Int(env["CLINICAL_WIDGET_MAX_LATENCY_MS"] ?? "") ?? defaultMaxLatencyMS
        let maxTotalMS = Int(env["CLINICAL_WIDGET_MAX_TOTAL_MS"] ?? "") ?? defaultMaxTotalMS
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Return to the Home Screen without leaving the main app running so widget extension execution is realistic.
        XCUIDevice.shared.press(.home)

        let nextButton = try findDailyTimelineWidget(in: springboard)
        let previousButton = springboard.buttons["Previous Day"].firstMatch
        let todayButton = springboard.buttons["Today"].firstMatch
        XCTAssertTrue(
            previousButton.existsOrWait(timeout: 3), "Previous Day button not found on widget")

        // Normalize to Today before measuring.
        if todayButton.exists {
            todayButton.tap()
            XCTAssertTrue(
                todayButton.absentOrWait(timeout: 15),
                "Widget did not return to Today during setup"
            )
            _ = measureUntil(timeout: 2.0) { false }
        }

        let headerKind = try detectHeaderElementKind(in: springboard, dayOffset: 0)
        let pollProbe = measureSingleQueryMS(in: springboard, kind: headerKind, dayOffset: 0)
        print("WIDGET_PERF header_kind=\(headerKind.rawValue) query_probe_ms=\(pollProbe)")

        let steps:
            [(label: String, button: XCUIElement, targetOffset: Int, expectTodayButton: Bool)] = [
                ("Next (0 -> +1) #1", nextButton, 1, true),
                ("Next (+1 -> +2) #1", nextButton, 2, true),
                ("Prev (+2 -> +1) #1", previousButton, 1, true),
                ("Today (+1 -> 0) #1", todayButton, 0, false),
                ("Prev (0 -> -1) #1", previousButton, -1, true),
                ("Today (-1 -> 0) #2", todayButton, 0, false),
                ("Next (0 -> +1) #2", nextButton, 1, true),
                ("Today (+1 -> 0) #3", todayButton, 0, false),
            ]

        var measurements: [TapMeasurement] = []
        for step in steps {
            XCTAssertTrue(
                step.button.hittableOrWait(timeout: 5),
                "Button not hittable before step: \(step.label)"
            )
            let expectedHeader = headerElement(
                in: springboard,
                kind: headerKind,
                dayOffset: step.targetOffset
            )
            let tapStart = ContinuousClock.now
            step.button.tap()
            let afterTapStart = ContinuousClock.now

            // Stop the timer on the single header query so we do not add a second SpringBoard
            // snapshot (~150ms on physical devices) after the widget has already updated.
            let elapsedAfterTap = measureUntil(timeout: 15.0) {
                expectedHeader.exists
            }
            let totalDuration = tapStart.duration(to: .now)
            let afterTapDuration = elapsedAfterTap ?? afterTapStart.duration(to: .now)
            XCTAssertEqual(
                todayButton.exists,
                step.expectTodayButton,
                "Unexpected Today button visibility after step: \(step.label)"
            )
            let measurement = TapMeasurement(
                label: step.label,
                totalMS: durationMS(totalDuration),
                afterTapMS: durationMS(afterTapDuration),
                timedOut: elapsedAfterTap == nil
            )
            measurements.append(measurement)
            print(
                "WIDGET_PERF step=\"\(measurement.label)\" total_ms=\(measurement.totalMS) after_tap_ms=\(measurement.afterTapMS) timed_out=\(measurement.timedOut)"
            )

            // Let any trailing system work settle briefly before the next measured tap.
            _ = measureUntil(timeout: 1.0) { false }
        }

        let afterTapValues = measurements.map(\.afterTapMS).sorted()
        let totalValues = measurements.map(\.totalMS).sorted()
        let medianAfterTap = afterTapValues[afterTapValues.count / 2]
        let maxAfterTap = afterTapValues.last ?? 0
        let medianTotal = totalValues[totalValues.count / 2]
        let maxTotal = totalValues.last ?? 0
        let summary =
            "WIDGET_PERF SUMMARY count=\(measurements.count) median_after_tap_ms=\(medianAfterTap) max_after_tap_ms=\(maxAfterTap) median_total_ms=\(medianTotal) max_total_ms=\(maxTotal) threshold_ms=\(maxLatencyMS) total_threshold_ms=\(maxTotalMS)"
        print(summary)

        // Verify 3 back-to-back taps on Next Day without polling between taps advance 3 days.
        let nextCoordinate = nextButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0..<3 {
            nextCoordinate.tap()
        }
        let rapidTargetHeader = headerElement(in: springboard, kind: headerKind, dayOffset: 3)
        XCTAssertTrue(
            rapidTargetHeader.existsOrWait(timeout: 5.0),
            "Three consecutive Next Day taps did not advance the widget by 3 days."
        )
        if todayButton.exists {
            todayButton.tap()
            _ = todayButton.absentOrWait(timeout: 5)
        }

        let reportLines =
            measurements.map {
                "\($0.label): after_tap=\($0.afterTapMS)ms total=\($0.totalMS)ms timed_out=\($0.timedOut)"
            } + [summary]
        let attachment = XCTAttachment(string: reportLines.joined(separator: "\n"))
        attachment.name = "DailyTimelineWidgetLatency"
        attachment.lifetime = .keepAlways
        add(attachment)

        for measurement in measurements {
            XCTAssertFalse(
                measurement.timedOut,
                "Widget did not update within 15s for \(measurement.label)"
            )
            XCTAssertLessThanOrEqual(
                measurement.afterTapMS,
                maxLatencyMS,
                "Widget update too slow after tap for \(measurement.label): \(measurement.afterTapMS)ms > \(maxLatencyMS)ms (total \(measurement.totalMS)ms)"
            )
            XCTAssertLessThanOrEqual(
                measurement.totalMS,
                maxTotalMS,
                "Widget update too slow end-to-end for \(measurement.label): \(measurement.totalMS)ms > \(maxTotalMS)ms (after_tap \(measurement.afterTapMS)ms)"
            )
        }
    }

    @MainActor
    private func findDailyTimelineWidget(in springboard: XCUIApplication) throws -> XCUIElement {
        let nextButton = springboard.buttons["Next Day"].firstMatch
        if nextButton.existsOrWait(timeout: 1.5), nextButton.isHittable {
            return nextButton
        }

        // Return to the first Home Screen page, then scan rightward pages.
        XCUIDevice.shared.press(.home)
        if nextButton.existsOrWait(timeout: 1.0), nextButton.isHittable {
            return nextButton
        }

        for _ in 0..<8 {
            springboard.swipeLeft()
            if nextButton.existsOrWait(timeout: 0.6), nextButton.isHittable {
                return nextButton
            }
        }

        // Also check the Today View to the left of page 1.
        XCUIDevice.shared.press(.home)
        springboard.swipeRight()
        if nextButton.existsOrWait(timeout: 1.0), nextButton.isHittable {
            return nextButton
        }

        XCTFail(
            "Daily Timeline widget (Next Day button) was not found on the Home Screen. Pin the Clinical Daily Timeline widget on the target device or simulator Home Screen."
        )
        throw NSError(domain: "DailyTimelineWidgetPerformanceUITests", code: 1)
    }

    #if targetEnvironment(simulator)
        @MainActor
        private func prepareSimulatorWidgetEnvironment() {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing-widget-perf-setup"]
            app.launch()
            XCTAssertTrue(
                app.staticTexts["Widget Perf Ready"].existsOrWait(timeout: 5),
                "App did not finish widget performance test setup."
            )
            app.terminate()
        }

        @MainActor
        private func cleanupSimulatorWidgetEnvironment() {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing-widget-perf-cleanup"]
            app.launch()
            _ = app.staticTexts["Widget Perf Ready"].existsOrWait(timeout: 5)
            app.terminate()
        }
    #endif

    @MainActor
    private func detectHeaderElementKind(
        in springboard: XCUIApplication,
        dayOffset: Int
    ) throws -> HeaderElementKind {
        for kind in [HeaderElementKind.button, .link, .staticText, .any] {
            if headerElement(in: springboard, kind: kind, dayOffset: dayOffset).exists {
                return kind
            }
        }
        let expected = formattedDateHeader(dayOffset: dayOffset)
        XCTFail("Could not find Today date header matching '\(expected)' on the widget.")
        throw NSError(domain: "DailyTimelineWidgetPerformanceUITests", code: 2)
    }

    @MainActor
    private func headerElement(
        in springboard: XCUIApplication,
        kind: HeaderElementKind,
        dayOffset: Int
    ) -> XCUIElement {
        let expected = formattedDateHeader(dayOffset: dayOffset)
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", expected)
        switch kind {
        case .button:
            return springboard.buttons.matching(predicate).firstMatch
        case .link:
            return springboard.links.matching(predicate).firstMatch
        case .staticText:
            return springboard.staticTexts.matching(predicate).firstMatch
        case .any:
            return springboard.descendants(matching: .any).matching(predicate).firstMatch
        }
    }

    @MainActor
    private func formattedDateHeader(dayOffset: Int) -> String {
        guard
            let date = TimelineUITestSupport.clinicCalendar.date(
                byAdding: .day,
                value: dayOffset,
                to: .now
            )
        else {
            preconditionFailure("Clinic calendar must support day offset arithmetic.")
        }
        return date.formatted(
            TimelineUITestSupport.clinicFormatStyle.weekday(.wide).day().month(.abbreviated)
        )
    }

    @MainActor
    private func measureSingleQueryMS(
        in springboard: XCUIApplication,
        kind: HeaderElementKind,
        dayOffset: Int
    ) -> Int {
        let start = ContinuousClock.now
        _ = headerElement(in: springboard, kind: kind, dayOffset: dayOffset).exists
        return durationMS(start.duration(to: .now))
    }

    private func durationMS(_ duration: Duration) -> Int {
        Int(
            (Double(duration.components.seconds) * 1000.0
                + Double(duration.components.attoseconds) / 1e15).rounded()
        )
    }
}
