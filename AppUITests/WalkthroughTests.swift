import XCTest

nonisolated final class WalkthroughTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor func testSeededWalkthroughSkipOpensToday() {
        let app = launch()
        defer { app.terminate() }
        assertPage(1, title: "Your plan on one timeline", in: app)
        let skip = app.buttons["walkthrough.skip"]
        XCTAssertTrue(skip.isHittable)
        skip.tap()
        assertToday(app)
    }

    @MainActor func testSeededWalkthroughNextNextDoneInDutchAtXXLarge() {
        let app = launch(language: "nl", xxLarge: true)
        defer { app.terminate() }
        assertPage(1, title: "Je plan op één tijdlijn", in: app, language: "nl")
        app.buttons["walkthrough.next"].tap()
        assertPage(2, title: "Herken elke stap in één oogopslag", in: app, language: "nl")
        app.buttons["walkthrough.next"].tap()
        assertPage(3, title: "Vink af wat je hebt gedaan", in: app, language: "nl")
        let done = app.buttons["walkthrough.done"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        assertToday(app)
    }

    @MainActor private func launch(language: String = "en", xxLarge: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_WALKTHROUGH_TEST_PENDING"] = "1"
        AuthUIFlow.launchSignedIn(app, walkthroughSeen: false, extraEnv: ["CF_AUTH_TEST_WALKTHROUGH_SEEN": "0"])
        return app
    }

    @MainActor private func assertPage(
        _ page: Int, title: String, in app: XCUIApplication, language: String = "en"
    ) {
        let counter = app.staticTexts["walkthrough.counter"]
        let changed = { counter.label == "\(page) \(language == "nl" ? "VAN" : "OF") 3" }
        XCTAssertTrue(UIWait.until(timeout: 12, condition: changed))
        XCTAssertEqual(app.staticTexts["walkthrough.title"].label, title)
        XCTAssertTrue(app.buttons["walkthrough.skip"].isHittable)
        XCTAssertTrue(app.buttons[page == 3 ? "walkthrough.done" : "walkthrough.next"].isHittable)
    }

    @MainActor private func assertToday(_ app: XCUIApplication) {
        XCTAssertTrue(app.scrollViews["today.screen"].waitUntil(.exists, timeout: 15))
        XCTAssertFalse(app.staticTexts["walkthrough.title"].exists)
    }
}
