import XCTest

nonisolated class SettingsPagesCase: ScreenTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 60
    }

    @MainActor fileprivate func assertReplayPage(_ number: Int, app: XCUIApplication) {
        let counter = app.staticTexts["walkthrough.counter"]
        let page = { counter.exists && counter.label == "\(number) OF 3" }
        XCTAssertTrue(
            UIWait.until(timeout: 6, condition: page),
            "Expected replay page \(number); counter: \(counter.exists ? counter.label : "missing")")
        let action = app.buttons[number == 3 ? "walkthrough.done" : "walkthrough.next"]
        AuthUIFlow.waitUntilEnabled(action)
    }

    @MainActor fileprivate func fillSecret(_ identifier: String, _ value: String, app: XCUIApplication) {
        let field = app.secureTextFields[identifier]
        XCTAssertTrue(field.waitUntil(.exists, timeout: 8))
        AuthUIFlow.type(value, into: field, in: app, newPassword: identifier != "settings.password.current")
    }

    @MainActor fileprivate func launchSettingsPages(
        route: String, account: AuthUIFlow.Account = .demo
    ) -> XCUIApplication {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments =
            AuthUIFlow.arguments() + ["-cf.settings.language", "system", "-cf.settings.theme", "system"]
        AuthUIFlow.launchSignedIn(app, walkthroughSeen: true, account: account, extraEnv: ["CF_SETTINGS_ROUTE": route])
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitUntil(.exists, timeout: 12))
        return app
    }

    @MainActor fileprivate func open(_ identifier: String, app: XCUIApplication) {
        let row = app.buttons[identifier]
        XCTAssertTrue(row.waitUntil(.exists, timeout: 8))
        AuthUIFlow.reveal(row, in: app)
        row.tap()
    }
}

nonisolated final class SettingsPagesTests: SettingsPagesCase {
    @MainActor func testBodyClockLargeTitleCollapsesOnScroll() throws {
        let app = launchSettingsPages(route: "bodyClock")
        let scroll = app.scrollViews["settings.bodyClock.screen"]
        let bar = app.navigationBars["Body clock"]
        let title = bar.staticTexts["Body clock"].firstMatch
        XCTAssertTrue(scroll.waitUntil(.hittable, timeout: 3))
        XCTAssertTrue(title.waitUntil(.exists, timeout: 3))
        let expanded = try UIWait.stableFrames([bar], timeout: 3)[0]

        scroll.swipeUp()

        XCTAssertTrue(
            UIWait.until(timeout: 3) {
                bar.frame.height < expanded.height && title.exists && title.isHittable
            },
            "Body clock should collapse into the inline navigation title after scrolling")
    }

    @MainActor func testProfileSaveShowsFeedbackAndUpdatedAccountRow() {
        let app = launchSettingsPages(route: "profile")
        let name = app.textFields["settings.profile.name"]
        XCTAssertTrue(name.waitUntil(.exists, timeout: 8))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (name.value as? String ?? "").count))
        name.typeText("Settings Test")
        let save = app.buttons["settings.profile.save"]
        AuthUIFlow.reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.staticTexts["settings.profile.saved"].waitUntil(.exists, timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["settings.account.profile"].label.contains("Settings Test"))
    }
    @MainActor func testBodyClockAutomaticallySavesAnswer() {
        let app = launchSettingsPages(route: "bodyClock")
        let chronotype = app.buttons["settings.bodyClock.chronotype.late"]
        XCTAssertTrue(chronotype.waitUntil(.exists, timeout: 8))
        AuthUIFlow.reveal(chronotype, in: app)
        chronotype.tap()
        let saved = app.staticTexts["settings.bodyClock.saved.about"]
        XCTAssertTrue(saved.waitUntil(.exists, timeout: 8))
        XCTAssertTrue(saved.isHittable)
        XCTAssertTrue(chronotype.isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("settings.bodyClock", app: app)
        XCTAssertTrue(app.buttons["settings.bodyClock.chronotype.late"].waitUntil(.exists, timeout: 8))
        XCTAssertTrue(app.buttons["settings.bodyClock.chronotype.late"].isSelected)
    }

    @MainActor func testPreferencesControlsAndReplaySkipAndDoneReturnHere() {
        let app = launchSettingsPages(route: "preferences")
        let format = app.buttons["settings.preferences.timeFormat.12"]
        XCTAssertTrue(format.waitUntil(.exists, timeout: 8))
        format.tap()
        assertSelected(format)
        let sleep = app.switches["settings.preferences.Sleep"]
        AuthUIFlow.reveal(sleep, in: app)
        sleep.tap()
        open("settings.preferences.replay", app: app)
        assertReplayPage(1, app: app)
        XCTAssertTrue(app.buttons["walkthrough.skip"].waitUntil(.exists, timeout: 8))
        app.buttons["walkthrough.skip"].tap()
        XCTAssertTrue(app.buttons["settings.preferences.replay"].waitUntil(.exists, timeout: 8))
        open("settings.preferences.replay", app: app)
        for index in 0..<3 {
            assertReplayPage(index + 1, app: app)
            let counter = app.staticTexts["walkthrough.counter"]
            let next = app.buttons[index == 2 ? "walkthrough.done" : "walkthrough.next"]
            do { _ = try UIWait.stableFrames([counter, next], timeout: 6) } catch { XCTFail("\(error)") }
            XCTAssertTrue(next.isHittable)
            next.tap()
        }
        XCTAssertTrue(app.buttons["settings.preferences.replay"].waitUntil(.exists, timeout: 8))
        let twentyFour = app.buttons["settings.preferences.timeFormat.24"]
        AuthUIFlow.reveal(twentyFour, in: app)
        twentyFour.tap()
        assertSelected(twentyFour)
    }

    @MainActor private func assertSelected(_ element: XCUIElement) {
        XCTAssertTrue(UIWait.until(timeout: 6) { element.exists && element.isSelected })
    }
    @MainActor func testLanguageChoiceUpdatesAppAndReturnsToAccount() {
        let app = launchSettingsPages(route: "language")
        let dutch = app.buttons["settings.language.choice.nl"]
        XCTAssertTrue(dutch.waitUntil(.exists, timeout: 8))
        dutch.tap()
        XCTAssertTrue(app.staticTexts["settings.language.saved"].waitUntil(.exists, timeout: 6))
        XCTAssertTrue(app.staticTexts["settings.language.saved"].label.contains("Nederlands"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["settings.account.language"].waitUntil(.exists, timeout: 6))
        XCTAssertTrue(app.buttons["settings.account.language"].label.contains("Taal"))
    }
    @MainActor func testPlanShowsStoredCreditsAndNoLinkState() {
        let app = launchSettingsPages(route: "plan")
        XCTAssertTrue(app.staticTexts["settings.plan.balance"].waitUntil(.exists, timeout: 8))
        XCTAssertTrue(app.staticTexts["settings.plan.noLink"].exists)
        XCTAssertFalse(app.buttons["Buy credits or a plan"].exists)
    }
}

nonisolated final class SettingsSecurityPagesTests: SettingsPagesCase {
    @MainActor func testPasswordFieldsSubmitAndShowFeedback() {
        let app = launchSettingsPages(route: "password")
        fillSecret("settings.password.current", MockScenarioValues.password, app: app)
        fillSecret("settings.password.new", "New password1!", app: app)
        fillSecret("settings.password.confirmation", "New password1!", app: app)
        open("settings.password.save", app: app)
        XCTAssertTrue(app.staticTexts["settings.security.feedback"].waitUntil(.exists, timeout: 8))
        XCTAssertEqual(app.staticTexts["settings.security.feedback"].label, "Password updated")
    }
    @MainActor func testSeededTwoFactorSetupConfirmsAndShowsRecoveryCodes() {
        let app = launchSettingsPages(route: "twoFactorSetup")
        let code = app.textFields["settings.twoFactor.code"]
        XCTAssertTrue(code.waitUntil(.exists, timeout: 12))
        XCTAssertTrue(app.staticTexts["settings.twoFactor.secret"].exists)
        AuthUIFlow.reveal(code, in: app)
        code.tap()
        code.typeText(MockScenarioValues.twoFactorCode)
        open("settings.twoFactor.confirm", app: app)
        XCTAssertTrue(
            app.staticTexts["settings.twoFactor.recoveryCode"].firstMatch.waitUntil(.exists, timeout: 8))
    }
    @MainActor func testEnabledTwoFactorCanCancelThenDisableAndReturnToIntroduction() {
        let app = launchSettingsPages(route: "twoFactor", account: .twofactor)
        open("settings.twoFactor.disable", app: app)
        XCTAssertTrue(app.secureTextFields["settings.security.prompt.password"].waitUntil(.exists, timeout: 6))
        XCTAssertTrue(app.buttons["settings.security.prompt.submit"].exists)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["settings.twoFactor.disable"].waitUntil(.exists, timeout: 6))
        open("settings.twoFactor.disable", app: app)
        let password = app.secureTextFields["settings.security.prompt.password"]
        XCTAssertTrue(password.waitUntil(.exists, timeout: 6))
        AuthUIFlow.type(MockScenarioValues.password, into: password, in: app)
        open("settings.security.prompt.submit", app: app)
        let enable = app.buttons["settings.twoFactor.enable"]
        XCTAssertTrue(enable.waitUntil(.exists, timeout: 8))
        AuthUIFlow.reveal(enable, in: app)
        XCTAssertTrue(enable.isHittable)
        XCTAssertFalse(app.buttons["settings.twoFactor.disable"].exists)
    }
    @MainActor func testDeleteConfirmationKeepsAccountAndOpensPasswordStage() {
        let app = launchSettingsPages(route: "delete")
        open("settings.delete.keep", app: app)
        XCTAssertTrue(app.buttons["settings.account.delete"].waitUntil(.exists, timeout: 6))
        open("settings.account.delete", app: app)
        open("settings.delete.confirm", app: app)
        XCTAssertTrue(app.secureTextFields["settings.delete.password"].waitUntil(.exists, timeout: 6))
        XCTAssertFalse(app.buttons["settings.delete.submit"].isEnabled)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["settings.account.delete"].waitUntil(.exists, timeout: 6))
    }
}
