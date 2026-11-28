import XCTest

nonisolated final class TimelineSharedSheetUITests: XCTestCase {
    @MainActor func testDoneWithoutPatientReopensSelection() {
        let app = TimelineUITestSupport.launch()
        TimelineUITestSupport.emptySpaceAbove(TimelineUITestSupport.original(app), in: app)
            .press(forDuration: 0.45)
        let search = app.textFields["Search patient by name"]
        XCTAssertTrue(search.hittableOrWait(timeout: 3))
        app.buttons["Back"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.hittableOrWait(timeout: 3))
        XCTAssertTrue(done.isEnabled)
        done.tap()
        XCTAssertTrue(search.hittableOrWait(timeout: 3))
        XCTAssertFalse(app.buttons["Add"].exists)
    }

    @MainActor func testPatientListSurvivesTypeChangesAndSheetReopening() {
        let app = TimelineUITestSupport.launch()
        XCTAssertTrue(app.tabBars.buttons["Schedule"].isSelected)
        app.buttons["Add"].tap()
        let search = app.textFields["Search patient by name"]
        let patient = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Test Patient")
        ).firstMatch
        XCTAssertTrue(search.hittableOrWait(timeout: 3))
        XCTAssertTrue(patient.existsOrWait(timeout: 3))
        XCTAssertFalse(app.tabBars.buttons["Schedule"].exists)

        for _ in 0..<2 {
            search.typeText("No matching patient")
            XCTAssertFalse(patient.exists)
            app.segmentedControls.buttons["Unavailable Time"].tap()
            XCTAssertTrue(app.textFields["Optional label"].existsOrWait(timeout: 3))
            app.segmentedControls.buttons["Appointment"].tap()
            XCTAssertTrue(search.hittableOrWait(timeout: 3))
            XCTAssertEqual(search.value as? String, "Search patient by name")
            XCTAssertTrue(patient.existsOrWait(timeout: 3))
        }

        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 3))
        TimelineUITestSupport.draft(app).tap()
        XCTAssertFalse(app.tabBars.buttons["Schedule"].exists)
        XCTAssertTrue(search.hittableOrWait(timeout: 3))
        XCTAssertTrue(patient.existsOrWait(timeout: 3))
        search.typeText("Test")
        XCTAssertTrue(patient.existsOrWait(timeout: 3))
        patient.tap()
        XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 3))
        XCTAssertTrue(TimelineUITestSupport.draft(app).label.contains("Test Patient"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Schedule"].isSelected)
    }

    @MainActor func testSharedSheetSwitchesFocusAndSwipeKeepsDraft() {
        let app = TimelineUITestSupport.launch()
        app.buttons["Add"].tap()
        let search = app.textFields["Search patient by name"]
        XCTAssertTrue(search.hittableOrWait(timeout: 3))
        // Typing without a tap verifies that the visible field received focus.
        search.typeText("Temporary search")
        app.segmentedControls.buttons["Unavailable Time"].tap()
        let label = app.textFields["Optional label"]
        XCTAssertTrue(label.hittableOrWait(timeout: 3))
        label.typeText("Travel")
        XCTAssertFalse(search.exists)
        app.segmentedControls.buttons["Appointment"].tap()
        XCTAssertTrue(search.hittableOrWait(timeout: 3))
        XCTAssertEqual(search.value as? String, "Search patient by name")
        search.typeText("New search")
        app.segmentedControls.buttons["Unavailable Time"].tap()
        XCTAssertTrue(label.hittableOrWait(timeout: 3))
        XCTAssertEqual(label.value as? String, "Optional label")
        label.typeText("Kept label")
        let bar = app.navigationBars["Unavailable Time"]
        let top = TimelineUITestSupport.coordinate(in: app, of: bar, dx: 0.5, dy: 0)
        top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 650)))
        XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 3))
        XCTAssertFalse(label.exists)
        let block = TimelineUITestSupport.newBlock(app)
        XCTAssertTrue(block.exists)
        XCTAssertEqual(block.value as? String, "30 min")
        block.tap()
        XCTAssertTrue(label.hittableOrWait(timeout: 3))
        XCTAssertEqual(label.value as? String, "Kept label")
        TimelineUITestSupport.attach(app, "Shared creation sheet after swipe and reopen", to: self)
    }

    @MainActor func testPatientCreationCancelKeepsSharedAppointmentSession() {
        let app = TimelineUITestSupport.launch()
        app.buttons["Add"].tap()
        let search = app.textFields["Search patient by name"]
        XCTAssertTrue(search.hittableOrWait(timeout: 3))
        search.typeText("New patient")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Add new patient")).firstMatch
            .tap()
        XCTAssertTrue(app.navigationBars["New Patient"].existsOrWait(timeout: 3))
        XCTAssertFalse(app.segmentedControls.buttons["Unavailable Time"].isHittable)
        app.buttons["Cancel"].tap()
        let keep = app.buttons["Discard Changes"]
        if keep.hittableOrWait(timeout: 1) { keep.tap() }
        XCTAssertTrue(search.hittableOrWait(timeout: 3))
        XCTAssertEqual(search.value as? String, "New patient")
        XCTAssertTrue(app.segmentedControls.buttons["Appointment"].isSelected)
    }

    @MainActor func testHoldSwitchToUnavailableTimeKeepsFirstDrag() {
        let app = TimelineUITestSupport.launch()
        TimelineUITestSupport.hold(
            TimelineUITestSupport.emptySpaceAbove(TimelineUITestSupport.original(app), in: app),
            move: 30)
        XCTAssertTrue(
            app.segmentedControls.buttons["Unavailable Time"].existsOrWait(timeout: 3))
        app.segmentedControls.buttons["Unavailable Time"].tap()
        app.buttons["Continue"].tap()
        let block = TimelineUITestSupport.newBlock(app)
        XCTAssertTrue(block.existsOrWait(timeout: 3))
        XCTAssertEqual(TimelineUITestSupport.time(block), "12:15 PM")
        XCTAssertEqual(block.value as? String, "30 min")
        XCTAssertFalse(TimelineUITestSupport.draft(app).exists)
        TimelineUITestSupport.attach(app, "Hold draft after type switch", to: self)
    }
}
