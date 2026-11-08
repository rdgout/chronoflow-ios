import XCTest

nonisolated final class SettingsPagesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor func testAccountProfileSavesNameThroughOutbox() {
        let app = launchSettingsPages()
        defer { app.terminate() }
        open("settings.account", app: app)
        open("settings.account.profile", app: app)
        let name = app.textFields["settings.profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (name.value as? String ?? "").count))
        name.typeText("Settings Test")
        let save = app.buttons["settings.profile.save"]
        AuthUIFlow.reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.staticTexts["settings.profile.saved"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["settings.account.profile"].label.contains("Settings Test"))
    }

    @MainActor private func launchSettingsPages() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
        app.launch()
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 12))
        app.tabBars.buttons["Settings"].tap()
        return app
    }

    @MainActor private func open(_ identifier: String, app: XCUIApplication) {
        let row = app.buttons[identifier]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        AuthUIFlow.reveal(row, in: app)
        row.tap()
    }
}
