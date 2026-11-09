import XCTest

nonisolated final class TermsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor func testAcceptanceOpensWalkthrough() {
        let app = launch()
        defer { app.terminate() }
        accept(app)
        XCTAssertTrue(app.staticTexts["walkthrough.title"].waitForMeasuredExistence(timeout: 12))
    }

    @MainActor func testDutchXXLargeAcceptedAccountGoesStraightToToday() {
        let app = launch(language: "nl", seen: true, xxLarge: true)
        defer { app.terminate() }
        XCTAssertEqual(app.staticTexts["terms.title"].label, "We hebben onze voorwaarden bijgewerkt")
        XCTAssertTrue(app.links["terms.policy"].exists)
        accept(app)
        XCTAssertTrue(app.scrollViews["today.screen"].waitForMeasuredExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["walkthrough.title"].exists)
    }

    @MainActor func testSignOutFromTermsWithNoChanges() {
        let app = launch()
        defer { app.terminate() }
        signOut(app)
        XCTAssertTrue(app.textFields["sign-in.email"].waitForMeasuredExistence(timeout: 12))
        XCTAssertFalse(app.staticTexts["terms.title"].exists)
        XCTAssertFalse(app.scrollViews["settings.pending"].exists)
    }

    @MainActor func testSignOutWithPendingChangesShowsConfirmation() {
        let app = launch(pendingChanges: true)
        defer { app.terminate() }
        signOut(app)
        let sheet = app.scrollViews["settings.pending"]
        XCTAssertTrue(sheet.waitForMeasuredExistence(timeout: 8))
    }

    @MainActor private func launch(
        language: String = "en", seen: Bool = false, xxLarge: Bool = false, pendingChanges: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_TERMS_PENDING"] = "1"
        app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = seen ? "1" : "0"
        if pendingChanges { app.launchEnvironment["CF_AUTH_TEST_TERMS_CHANGES_PENDING"] = "1" }
        AuthUIFlow.launchSignedIn(app, walkthroughSeen: seen)
        XCTAssertTrue(app.staticTexts["terms.title"].waitForMeasuredExistence(timeout: 12))
        return app
    }

    @MainActor private func accept(_ app: XCUIApplication) {
        let button = app.buttons["terms.accept"]
        AuthUIFlow.reveal(button, in: app)
        AuthUIFlow.waitUntilEnabled(button)
        button.tap()
    }

    @MainActor private func signOut(_ app: XCUIApplication) {
        let button = app.buttons["terms.signOut"]
        AuthUIFlow.reveal(button, in: app)
        AuthUIFlow.waitUntilEnabled(button)
        button.tap()
    }
}
