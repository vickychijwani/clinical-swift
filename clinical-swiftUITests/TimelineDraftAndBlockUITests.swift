import XCTest

nonisolated final class TimelineDraftAndBlockUITests: XCTestCase {
    @MainActor func testHoldOnUnavailableTimeEntersMoveModeAtTheSameTime() {
        let app = TimelineUITestSupport.launch()
        let block = app.buttons["unavailable-time-00000000-0000-0000-0000-000000000014"]
        XCTAssertTrue(block.exists)
        block.press(forDuration: 0.45)
        XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 3))
        XCTAssertEqual(TimelineUITestSupport.time(block), "11:00 AM")
        XCTAssertFalse(app.textFields["Optional label"].exists)
        XCTAssertFalse(app.textFields["Search patient by name"].exists)
        TimelineUITestSupport.drag(block, in: app, by: 15)
        XCTAssertEqual(TimelineUITestSupport.time(block), "11:15 AM")
        app.buttons["Cancel"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 3))
        XCTAssertEqual(TimelineUITestSupport.time(block), "11:00 AM")
    }

    @MainActor func testUnavailableTimeTapMovesResizesAndCancelRestoresStoredBlock() {
        let app = TimelineUITestSupport.launch()
        let block = app.buttons["unavailable-time-00000000-0000-0000-0000-000000000014"]
        block.tap()
        XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 3))
        XCTAssertFalse(app.textFields["Optional label"].exists)
        XCTAssertTrue(app.buttons["Delete"].exists)
        XCTAssertGreaterThan(block.frame.width, 300)
        TimelineUITestSupport.drag(block, in: app, by: 15)
        XCTAssertEqual(TimelineUITestSupport.time(block), "11:15 AM")
        XCTAssertFalse(app.textFields["Optional label"].exists)
        let handle = app.otherElements["unavailable-time-duration-handle"]
        XCTAssertTrue(handle.exists)
        TimelineUITestSupport.drag(handle, in: app, by: -100)
        XCTAssertEqual(TimelineUITestSupport.time(block), "11:15 AM")
        XCTAssertEqual(block.value as? String, "15 min")
        TimelineUITestSupport.attach(app, "Unavailable time with shared card controls", to: self)
        app.buttons["Cancel"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 3))
        XCTAssertEqual(TimelineUITestSupport.time(block), "11:00 AM")
        XCTAssertEqual(block.value as? String, "30 min")
    }

    @MainActor func testUnavailableTimeCreationLabelReturnsToDraftAndCanReopen() {
        let app = TimelineUITestSupport.launch()
        app.buttons["Add"].tap()
        app.segmentedControls.buttons["Unavailable Time"].tap()
        let label = app.textFields["Optional label"]
        XCTAssertTrue(label.hittableOrWait(timeout: 3))
        label.tap()
        label.typeText("Holiday")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 3))
        let block = TimelineUITestSupport.newBlock(app)
        XCTAssertEqual(block.value as? String, "30 min")
        XCTAssertFalse(app.buttons["Delete"].exists)
        TimelineUITestSupport.drag(block, in: app, by: 15)
        let movedTime = TimelineUITestSupport.time(block)
        XCTAssertFalse(label.exists)
        block.tap()
        XCTAssertTrue(label.hittableOrWait(timeout: 3))
        XCTAssertEqual(label.value as? String, "Holiday")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Done"].hittableOrWait(timeout: 3))
        XCTAssertEqual(TimelineUITestSupport.time(block), movedTime)
        let id = block.identifier
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 3))
        XCTAssertEqual(TimelineUITestSupport.time(app.buttons[id]), movedTime)
    }

    @MainActor func testUnavailableTimeDeleteConfirmsAtCard() {
        let app = TimelineUITestSupport.launch()
        let block = app.buttons["unavailable-time-00000000-0000-0000-0000-000000000014"]
        block.tap()
        XCTAssertTrue(app.buttons["Delete"].hittableOrWait(timeout: 3))
        let delete = app.buttons["Delete"]
        XCTAssertGreaterThan(delete.frame.minY, block.frame.maxY)
        delete.tap()
        let confirm = app.buttons["Delete Unavailable Time"]
        XCTAssertTrue(confirm.hittableOrWait(timeout: 3))
        XCTAssertTrue(block.exists)
        TimelineUITestSupport.attach(app, "Unavailable time delete confirmation", to: self)
        confirm.tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 3))
        XCTAssertFalse(block.exists)
    }

    @MainActor func testSelectedDraftCanMoveResizeAndCancel() {
        let app = TimelineUITestSupport.launch(arguments: ["--ui-testing-selected-draft"])
        let draft = TimelineUITestSupport.draft(app)
        TimelineUITestSupport.drag(draft, in: app, by: 15)
        XCTAssertEqual(TimelineUITestSupport.time(draft), "12:15 PM")
        let handle = app.otherElements["appointment-duration-handle"]
        XCTAssertTrue(handle.exists)
        TimelineUITestSupport.drag(handle, in: app, by: -100)
        XCTAssertEqual(TimelineUITestSupport.time(draft), "12:15 PM")
        XCTAssertEqual(draft.value as? String, "15 min")
        XCTAssertFalse(app.otherElements["appointment-start-handle"].exists)
        let id = draft.identifier
        app.buttons["Cancel"].tap()
        let discard = app.buttons["Discard Changes"]
        XCTAssertTrue(discard.hittableOrWait(timeout: 3))
        TimelineUITestSupport.attach(app, "Cancel confirmation anchored to card button", to: self)
        discard.tap()
        XCTAssertTrue(app.buttons["Add"].hittableOrWait(timeout: 3))
        XCTAssertFalse(app.buttons[id].exists)
        XCTAssertEqual(
            TimelineUITestSupport.time(TimelineUITestSupport.original(app)), "12:00 PM")
    }

    @MainActor func testDraftOverBreakExpandsAndMovingOutCollapses() {
        let app = TimelineUITestSupport.launch(arguments: ["--ui-testing-selected-draft"])
        let draft = TimelineUITestSupport.draft(app)
        let initialY = draft.frame.minY
        TimelineUITestSupport.drag(draft, in: app, by: 76, dwell: 0.9)
        XCTAssertEqual(TimelineUITestSupport.time(draft), "2:30 PM")
        XCTAssertEqual(draft.frame.minY, initialY + 76, accuracy: 8)
        XCTAssertTrue(app.staticTexts["2\u{202f}PM"].exists)
        TimelineUITestSupport.attach(app, "Expanded break", to: self)
        TimelineUITestSupport.drag(draft, in: app, by: -110)
        XCTAssertEqual(TimelineUITestSupport.time(draft), "12:40 PM")
        XCTAssertFalse(app.staticTexts["2\u{202f}PM"].exists)
    }
}
