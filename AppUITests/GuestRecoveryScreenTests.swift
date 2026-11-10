import XCTest

nonisolated final class GuestRecoveryScreenTests: ScreenTestCase {
    @MainActor func testWelcomeHandsOverToRecoveredSleep() {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment = ["CF_GUEST_RECOVERY_BOARD": "WizardSleep"]
        app.launchMeasured()
        XCTAssertTrue(app.buttons["wizard.sleep.continue"].waitUntil(.hittable, timeout: 5))
        XCTAssertTrue(app.datePickers["wizard.sleep.habitual_bed"].exists)
        XCTAssertFalse(app.images["launch.opening"].exists)
        XCTAssertFalse(app.buttons["welcome.plan"].exists)
    }
}
