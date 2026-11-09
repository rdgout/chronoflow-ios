import XCTest

nonisolated final class AppTabsTests: XCTestCase {
    @MainActor func testSignedInAccountCanSwitchAllThreeTabs() {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
        app.launch()
        defer { app.terminate() }
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        XCTAssertTrue(app.tabBars.buttons["My trips"].waitForExistence(timeout: 12))
        app.tabBars.buttons["My trips"].tap()
        XCTAssertTrue(app.staticTexts["route.trips"].waitForExistence(timeout: 4))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["route.settings"].waitForExistence(timeout: 4))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 4))
    }
}
