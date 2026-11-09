import XCTest

nonisolated final class TermsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor func testAcceptanceOpensWalkthroughAndOfflineRelaunchKeepsAcceptance() {
        let app = launch()
        defer { app.terminate() }
        accept(app)
        XCTAssertTrue(app.staticTexts["walkthrough.title"].waitForExistence(timeout: 12))
        app.terminate()
        app.launchEnvironment["CF_AUTH_TEST_OFFLINE"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["walkthrough.title"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["terms.title"].exists)
        app.buttons["walkthrough.skip"].tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["terms.title"].exists)
    }

    @MainActor func testDutchXXLargeAcceptedAccountGoesStraightToToday() {
        let app = launch(language: "nl", seen: true, xxLarge: true)
        defer { app.terminate() }
        XCTAssertEqual(app.staticTexts["terms.title"].label, "We hebben onze voorwaarden bijgewerkt")
        XCTAssertTrue(app.links["terms.policy"].exists)
        accept(app)
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["walkthrough.title"].exists)
    }

    @MainActor func testSignOutFromTermsWithNoChanges() {
        let app = launch()
        defer { app.terminate() }
        signOut(app)
        XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.staticTexts["terms.title"].exists)
        XCTAssertFalse(app.scrollViews["settings.pending"].exists)
    }

    @MainActor func testSignOutWithPendingChangesCanStayThenDiscard() {
        let app = launch(pendingChanges: true)
        defer { app.terminate() }
        signOut(app)
        let sheet = app.scrollViews["settings.pending"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        let stay = app.buttons["settings.pending.stay"]
        AuthUIFlow.reveal(stay, in: app, scroll: sheet)
        stay.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !sheet.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 4), .completed)
        XCTAssertTrue(app.staticTexts["terms.title"].exists)
        signOut(app)
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        let discard = app.buttons["settings.pending.discard"]
        AuthUIFlow.reveal(discard, in: app, scroll: sheet)
        discard.tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 12))
    }

    @MainActor private func launch(
        language: String = "en", seen: Bool = false, xxLarge: Bool = false, pendingChanges: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_TERMS_PENDING"] = "1"
        if seen { app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1" }
        if pendingChanges { app.launchEnvironment["CF_AUTH_TEST_TERMS_CHANGES_PENDING"] = "1" }
        app.launch()
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        XCTAssertTrue(app.staticTexts["terms.title"].waitForExistence(timeout: 12))
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
