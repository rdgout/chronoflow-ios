import XCTest

nonisolated final class UIReseedTests: ScreenTestCase {
    @MainActor func testReseedReplacesAccountAndDismissesPresentedStepSheet() throws {
        let app = try launchPlanAccount(freezePlanClock: true)
        let rows = app.scrollViews["today.screen"].buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.step.actionable."))
        let row = rows.firstMatch
        XCTAssertTrue(row.waitUntil(.exists, timeout: 12))
        AuthUIFlow.reveal(row, in: app, scroll: app.scrollViews["today.screen"])
        row.tap()
        XCTAssertTrue(app.scrollViews["step.sheet"].waitUntil(.exists, timeout: 4))
        let launches = ScreenTestApp.coldLaunches
        let resets = ScreenTestApp.reseeds
        let replacement = ScreenTestApp.makeApplication()
        replacement.launchArguments = AuthUIFlow.arguments()
        AuthUIFlow.launchSignedIn(
            replacement, walkthroughSeen: true, account: .twofactor, extraEnv: ["CF_SETTINGS_ROUTE": "security"])
        XCTAssertTrue(replacement.buttons["settings.security.twoFactor"].waitUntil(.exists, timeout: 12))
        XCTAssertFalse(replacement.scrollViews["step.sheet"].exists)
        XCTAssertEqual(ScreenTestApp.coldLaunches, launches)
        XCTAssertEqual(ScreenTestApp.reseeds, resets + 1)
        let signedOut = ScreenTestApp.makeApplication()
        signedOut.launchArguments = AuthUIFlow.arguments()
        signedOut.launchMeasured()
        XCTAssertTrue(signedOut.buttons["welcome.signIn"].waitUntil(.exists, timeout: 8))
        XCTAssertFalse(signedOut.tabBars.firstMatch.exists)
        XCTAssertEqual(ScreenTestApp.coldLaunches, launches)
        XCTAssertEqual(ScreenTestApp.reseeds, resets + 2)
    }

    @MainActor func testFreshSeedHasTheOriginalProfile() {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments = AuthUIFlow.arguments()
        AuthUIFlow.launchSignedIn(app, walkthroughSeen: true, extraEnv: ["CF_SETTINGS_ROUTE": "profile"])
        let name = app.textFields["settings.profile.name"]
        XCTAssertTrue(name.waitUntil(.exists, timeout: 8))
        XCTAssertEqual(name.value as? String, "Demo Traveller")
        name.tap()
        name.typeText(" changed")
    }
}
