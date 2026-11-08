import XCTest

nonisolated final class PlanAuditTests: XCTestCase {
    @MainActor func testTodayPrimaryState() throws { try audit { _ in } }
    @MainActor func testStepSheetPrimaryState() throws {
        try audit { app in
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.step.actionable."))
                .firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 12))
            AuthUIFlow.reveal(row, in: app, scroll: app.scrollViews["today.screen"])
            row.tap()
            XCTAssertTrue(app.scrollViews["step.sheet"].waitForExistence(timeout: 4))
        }
    }
    @MainActor func testLegendPrimaryState() throws {
        try audit(legend: true) { app in
            XCTAssertTrue(app.scrollViews["legend.sheet"].waitForExistence(timeout: 4))
        }
    }
    @MainActor private func audit(legend: Bool = false, _ navigate: (XCUIApplication) -> Void) throws {
        let appearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = appearance }
        try DeviceAppearance.set(.light)
        let app = launchPlanAccount(presentLegend: legend)
        defer { app.terminate() }
        navigate(app)
        try app.performAccessibilityAudit()
    }
}
