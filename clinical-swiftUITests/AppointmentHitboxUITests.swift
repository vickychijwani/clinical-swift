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
}
