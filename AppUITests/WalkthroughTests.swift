import XCTest

nonisolated final class WalkthroughTests: XCTestCase {
    @MainActor func testFreshMockSkipOpensTodayAndOfflineRelaunchKeepsPendingCompletion() {
        let app = launch()
        defer { app.terminate() }
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        assertPage(1, title: "Your plan on one timeline", in: app)
        let skip = app.buttons["walkthrough.skip"]
        XCTAssertTrue(skip.isHittable)
        skip.tap()
        assertTodayAndRelaunch(app)
    }

    @MainActor func testAnotherMockAccountNextNextDoneInDutchAtXXLargeAndOfflineRelaunch() {
        let app = launch(language: "nl", xxLarge: true)
        defer { app.terminate() }
        AuthUIFlow.signIn(app, email: MockScenarioValues.twoFactorEmail)
        let code = app.textFields["two-factor.code"]
        guard code.waitForExistence(timeout: 8) else {
            XCTFail("Expected the second account's two-factor challenge")
            return
        }
        AuthUIFlow.reveal(code, in: app)
        code.tap()
        code.typeText(MockScenarioValues.twoFactorCode)
        let verify = app.buttons["two-factor.submit"]
        AuthUIFlow.reveal(verify, in: app)
        AuthUIFlow.waitUntilEnabled(verify)
        verify.tap()
        assertPage(1, title: "Je plan op één tijdlijn", in: app, language: "nl")
        app.buttons["walkthrough.next"].tap()
        assertPage(2, title: "Herken elke stap in één oogopslag", in: app, language: "nl")
        app.buttons["walkthrough.next"].tap()
        assertPage(3, title: "Vink af wat je hebt gedaan", in: app, language: "nl")
        let done = app.buttons["walkthrough.done"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        assertTodayAndRelaunch(app)
    }

    @MainActor private func launch(language: String = "en", xxLarge: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_WALKTHROUGH_TEST_PENDING"] = "1"
        app.launch()
        AuthUIFlow.openSignIn(app)
        return app
    }

    @MainActor private func assertPage(
        _ page: Int, title: String, in app: XCUIApplication, language: String = "en"
    ) {
        let counter = app.staticTexts["walkthrough.counter"]
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "\(page) \(language == "nl" ? "VAN" : "OF") 3"),
            object: counter)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 12), .completed)
        XCTAssertEqual(app.staticTexts["walkthrough.title"].label, title)
        XCTAssertTrue(app.buttons["walkthrough.skip"].isHittable)
        XCTAssertTrue(app.buttons[page == 3 ? "walkthrough.done" : "walkthrough.next"].isHittable)
    }

    @MainActor private func assertTodayAndRelaunch(_ app: XCUIApplication) {
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["walkthrough.title"].exists)
        app.terminate()
        app.launchEnvironment["CF_AUTH_TEST_OFFLINE"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["walkthrough.title"].exists)
        XCTAssertFalse(app.buttons["welcome.signIn"].exists)
    }
}
