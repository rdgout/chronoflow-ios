import XCTest

nonisolated final class TripPageStepTests: XCTestCase {
    @MainActor func testSeededTimelineAndListOpenTheSameStepSheet() {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments() + ["-cf.trip-page", "S1", "-cf.session", "out"]
        app.launch()
        defer { app.terminate() }
        let blockID = "sleep-sleep-29865450"
        let scroll = app.scrollViews["trip.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 12))
        XCTAssertTrue(
            app.descendants(matching: .any)["trip.timeline.ready"].firstMatch.waitForExistence(timeout: 12))
        tapBlock(blockID, app: app, scroll: scroll)
        assertStepContent(app)
        let title = stepText("step.title", in: app).label
        let time = stepText("step.time", in: app).label.components(separatedBy: " · ").first
        dismissSheet(app)
        app.buttons["trip.viewToggle"].tap()
        tapBlock(blockID, app: app, scroll: scroll)
        assertStepContent(app)
        XCTAssertEqual(stepText("step.title", in: app).label, title)
        XCTAssertEqual(stepText("step.time", in: app).label.components(separatedBy: " · ").first, time)
    }

    @MainActor func testSeededTodayTripStepActionsUpdateAndSurviveListReopen() throws {
        let app = try launchPlanAccount(freezePlanClock: true)
        defer { app.terminate() }
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.step.actionable."))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        let blockID = String(row.identifier.dropFirst("today.step.actionable.".count))
        XCTAssertFalse(blockID.isEmpty)
        app.buttons["today.trip"].tap()
        let scroll = app.scrollViews["trip.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)["trip.timeline.ready"].firstMatch.waitForExistence(timeout: 12))
        tapBlock(blockID, app: app, scroll: scroll)
        assertStepContent(app)
        let done = app.buttons["step.done"]
        let skip = app.buttons["step.skip"]
        let undo = app.buttons["step.undo"]
        tapAction(skip, app: app, tapping: false)
        tapAction(done, app: app)
        tapAction(undo, app: app)
        tapAction(skip, app: app)
        XCTAssertTrue(undo.waitForExistence(timeout: 6))
        dismissSheet(app)
        app.buttons["trip.viewToggle"].tap()
        tapBlock(blockID, app: app, scroll: scroll)
        assertStepContent(app)
        tapAction(undo, app: app)
        tapAction(done, app: app, tapping: false)
        tapAction(skip, app: app, tapping: false)
    }

    @MainActor private func tapAction(_ action: XCUIElement, app: XCUIApplication, tapping: Bool = true) {
        XCTAssertTrue(action.waitForExistence(timeout: 6))
        AuthUIFlow.reveal(action, in: app, scroll: app.scrollViews["step.sheet"])
        XCTAssertTrue(action.isHittable)
        if tapping { action.tap() }
    }

    @MainActor private func assertStepContent(_ app: XCUIApplication) {
        XCTAssertTrue(app.scrollViews["step.sheet"].waitForExistence(timeout: 4), app.debugDescription)
        let title = stepText("step.title", in: app)
        let time = stepText("step.time", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        XCTAssertTrue(title.isHittable)
        XCTAssertFalse(title.label.isEmpty)
        XCTAssertTrue(time.waitForExistence(timeout: 4))
        XCTAssertTrue(time.isHittable)
        XCTAssertNotNil(time.label.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression))
        XCTAssertTrue(time.label.contains("time"))
        XCTAssertFalse(app.staticTexts["step.gone"].exists)
    }

    @MainActor private func tapBlock(_ id: String, app: XCUIApplication, scroll: XCUIElement) {
        let block = app.buttons["trip.block.\(id)"].firstMatch
        for _ in 0..<12 {
            let viewport = AuthUIFlow.viewport(in: app, scrollFrame: scroll.frame).insetBy(dx: 0, dy: 44)
            if block.exists {
                let visible = block.frame.intersection(viewport)
                if !visible.isNull && visible.width > 0 && visible.height > 8 {
                    app.coordinate(withNormalizedOffset: .zero).withOffset(
                        CGVector(dx: visible.midX, dy: visible.midY)
                    ).tap()
                    return
                }
                if block.frame.maxY < viewport.minY {
                    scroll.swipeDown()
                    continue
                }
            }
            scroll.swipeUp()
        }
        XCTFail("Cannot reach timeline/list block \(id): \(app.debugDescription)")
    }

    @MainActor private func dismissSheet(_ app: XCUIApplication) {
        let sheet = app.scrollViews["step.sheet"]
        for _ in 0..<6 where sheet.exists {
            sheet.swipeDown()
            if sheet.waitForNonExistence(timeout: 1) { break }
        }
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 4), app.debugDescription)
    }

    @MainActor private func stepText(_ context: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier ENDSWITH %@", "|" + context)).firstMatch
    }
}
