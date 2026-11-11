import DesignSystem
import XCTest

nonisolated final class TripPageStepTests: ScreenTestCase {
    @MainActor func testTripBlockActionsAndListReopen() throws {
        let app = try launchPlanAccount(
            freezePlanClock: true, route: "trip:\(PlanUIFlow.blockTripID)", blockID: PlanUIFlow.blockID)
        let block = app.buttons["trip.block.\(PlanUIFlow.blockID)"].firstMatch
        XCTAssertTrue(block.waitUntil(.hittable, timeout: 4))
        block.tap()
        assertStepContent(app)
        tapAction("step.done", in: app)
        tapAction("step.undo", in: app)
        tapAction("step.skip", in: app)
        XCTAssertTrue(app.buttons["step.undo"].waitUntil(.hittable, timeout: 3))
        let sheet = app.scrollViews["step.sheet"]
        let start = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(sheet.waitUntil(.gone, timeout: 3))
        app.buttons["trip.viewToggle"].tap()
        XCTAssertTrue(block.waitUntil(.hittable, timeout: 3))
        block.tap()
        XCTAssertTrue(sheet.waitUntil(.exists, timeout: 3))
        XCTAssertTrue(app.buttons["step.undo"].waitUntil(.hittable, timeout: 3))
    }

    @MainActor private func tapAction(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitUntil(.hittable, timeout: 3))
        button.tap()
    }

    @MainActor private func assertStepContent(_ app: XCUIApplication) {
        XCTAssertTrue(app.scrollViews["step.sheet"].waitUntil(.exists, timeout: 3))
        let title = app.staticTexts[
            Typography.screenCardTitle.planTextIdentifier(color: .foreground, context: "step.title")
        ].firstMatch
        let time = app.staticTexts[
            Typography.screenBody.planTextIdentifier(color: .mutedForeground, context: "step.time")
        ].firstMatch
        XCTAssertTrue(title.waitUntil(.hittable, timeout: 3))
        XCTAssertFalse(title.label.isEmpty)
        XCTAssertTrue(time.isHittable)
        XCTAssertNotNil(time.label.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression))
    }
}
