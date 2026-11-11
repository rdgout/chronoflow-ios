import XCTest

nonisolated final class BodyClockPrivacyScreenTests: ScreenTestCase {
    override func setUp() async throws {
        try await super.setUp()
        executionTimeAllowance = 60
    }

    @MainActor func testCaffeineUsesANativePreferenceToggle() {
        let app = launch()
        let toggle = app.switches["settings.bodyClock.excludeCaffeine"]
        AuthUIFlow.reveal(toggle, in: app)
        XCTAssertTrue(toggle.isHittable)
        XCTAssertTrue(toggle.label.contains("Leave caffeine out of my plan"))
    }

    @MainActor func testMovementUsesANativePreferenceToggleWithHelp() {
        let app = launch()
        let toggle = app.switches["settings.bodyClock.flightMovementBreaks"]
        AuthUIFlow.reveal(toggle, in: app)
        XCTAssertTrue(toggle.isHittable)
        XCTAssertTrue(toggle.label.contains("compression stockings and an aisle seat"))
    }

    @MainActor func testLightDeviceNoticeIsText() {
        let app = launch()
        let notice = app.staticTexts["settings.bodyClock.lightNotice"]
        AuthUIFlow.reveal(notice, in: app)
        XCTAssertTrue(notice.isHittable)
        XCTAssertTrue(notice.label.contains("Ask your doctor first."))
    }

    @MainActor func testAudienceNoticeIsText() {
        let app = launch()
        let notice = app.staticTexts["settings.bodyClock.audienceNotice"]
        AuthUIFlow.reveal(notice, in: app)
        XCTAssertTrue(notice.isHittable)
        XCTAssertTrue(notice.label.contains("manic or hypomanic episode"))
    }

    @MainActor func testAdjustedReadinessUsesPreferencesAndAgeCopy() {
        let app = launch(state: "bodyAdjusted")
        XCTAssertTrue(app.staticTexts["Your plan is adjusted for your preferences and age range"].exists)
        XCTAssertTrue(app.staticTexts["No caffeine anywhere in your plan."].exists)
    }

    @MainActor private func launch(state: String = "bodyReady") -> XCUIApplication {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments = AuthUIFlow.arguments()
        AuthUIFlow.launchSignedIn(
            app, walkthroughSeen: true,
            extraEnv: ["CF_SETTINGS_ROUTE": "bodyClock", "CF_SETTINGS_BOARD_STATE": state])
        XCTAssertTrue(app.buttons["settings.bodyClock.chronotype.early"].waitUntil(.exists, timeout: 3))
        return app
    }
}
