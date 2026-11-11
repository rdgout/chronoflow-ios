import XCTest

nonisolated final class TripWizardTests: ScreenTestCase {
    override func setUp() async throws {
        try await super.setUp()
        executionTimeAllowance = 60
    }

    @MainActor func testOneWayReviewAndSaveOpensTripPage() {
        let app = WizardScreenUIFlow.launch("WizardSaveJourney")
        app.buttons["wizard.choice.one-way"].tap()
        let fineTune = app.buttons["wizard.fine-tune.continue"]
        XCTAssertTrue(fineTune.waitUntil(.hittable, timeout: 5))
        fineTune.tap()
        let save = app.buttons["wizard.ready.continue"]
        XCTAssertTrue(save.waitUntil(.enabled, timeout: 3))
        save.tap()
        XCTAssertTrue(app.scrollViews["trip.scroll"].waitUntil(.exists, timeout: 5))
    }
}
