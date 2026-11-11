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

    @MainActor func testBodyClockAutomaticallySavesAnswer() {
        let app = launchSettingsPages()
        defer { app.terminate() }
        open("settings.bodyClock", app: app)
        let chronotype = app.buttons["settings.bodyClock.chronotype.late"]
        XCTAssertTrue(chronotype.waitForExistence(timeout: 8))
        AuthUIFlow.reveal(chronotype, in: app)
        chronotype.tap()
        let saved = app.descendants(matching: .any)["settings.bodyClock.saved.about"]
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        XCTAssertTrue(saved.isHittable)
        XCTAssertTrue(chronotype.isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("settings.bodyClock", app: app)
        XCTAssertTrue(app.buttons["settings.bodyClock.chronotype.late"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["settings.bodyClock.chronotype.late"].isSelected)
    }

    @MainActor func testPreferencesSavesAndReplaySkipAndDoneReturnHere() {
        let app = launchSettingsPages()
        defer { app.terminate() }
        open("settings.preferences", app: app)
        let format = app.buttons["settings.preferences.timeFormat.12"]
        XCTAssertTrue(format.waitForExistence(timeout: 8))
        format.tap()
        assertSelected(format)
        let sleep = app.switches["settings.preferences.Sleep"]
        AuthUIFlow.reveal(sleep, in: app)
        sleep.tap()
        open("settings.preferences.replay", app: app)
        assertReplayPage(1, app: app)
        XCTAssertTrue(app.buttons["walkthrough.skip"].waitForExistence(timeout: 8))
        app.buttons["walkthrough.skip"].tap()
        XCTAssertTrue(app.buttons["settings.preferences.replay"].waitForExistence(timeout: 8))
        open("settings.preferences.replay", app: app)
        for index in 0..<3 {
            assertReplayPage(index + 1, app: app)
            let counter = app.staticTexts["walkthrough.counter"]
            let next = app.buttons[index == 2 ? "walkthrough.done" : "walkthrough.next"]
            do { _ = try UIWait.stableFrames([counter, next], timeout: 6) } catch { XCTFail("\(error)") }
            XCTAssertTrue(next.isHittable)
            next.tap()
        }
        XCTAssertTrue(app.buttons["settings.preferences.replay"].waitForExistence(timeout: 8))
        let twentyFour = app.buttons["settings.preferences.timeFormat.24"]
        AuthUIFlow.reveal(twentyFour, in: app)
        twentyFour.tap()
        assertSelected(twentyFour)
    }

    @MainActor private func assertSelected(_ element: XCUIElement) {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in element.exists && element.isSelected }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 6), .completed)
    }

    @MainActor private func assertReplayPage(_ number: Int, app: XCUIApplication) {
        let counter = app.staticTexts["walkthrough.counter"]
        let page = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", "\(number) OF 3"), object: counter)
        XCTAssertEqual(
            XCTWaiter.wait(for: [page], timeout: 6), .completed,
            "Expected replay page \(number); counter: \(counter.exists ? counter.label : "missing")")
        let action = app.buttons[number == 3 ? "walkthrough.done" : "walkthrough.next"]
        AuthUIFlow.waitUntilEnabled(action)
    }

    @MainActor func testLanguageChoiceUpdatesAppAndReturnsToAccount() {
        let app = launchSettingsPages()
        defer { app.terminate() }
        open("settings.account", app: app)
        open("settings.account.language", app: app)
        let dutch = app.buttons["settings.language.choice.nl"]
        XCTAssertTrue(dutch.waitForExistence(timeout: 8))
        dutch.tap()
        XCTAssertTrue(app.staticTexts["settings.language.saved"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["settings.language.saved"].label.contains("Nederlands"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["settings.account.language"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["settings.account.language"].label.contains("Taal"))
    }

    @MainActor func testSecurityPasswordAndTwoFactorSetupCodesAndDisable() {
        let app = launchSettingsPages()
        defer { app.terminate() }
        open("settings.security", app: app)
        open("settings.security.password", app: app)
        fillSecret("settings.password.current", "password", app: app)
        fillSecret("settings.password.new", "New password1!", app: app)
        fillSecret("settings.password.confirmation", "New password1!", app: app)
        open("settings.password.save", app: app)
        XCTAssertTrue(app.staticTexts["settings.security.feedback"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["settings.security.feedback"].label, "Password updated")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("settings.security.twoFactor", app: app)
        open("settings.twoFactor.enable", app: app)
        fillSecret("settings.security.prompt.password", "New password1!", app: app)
        open("settings.security.prompt.submit", app: app)
        XCTAssertTrue(app.buttons["settings.security.prompt.submit"].waitForNonExistence(timeout: 8))
        let code = app.textFields["settings.twoFactor.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        let form = app.descendants(matching: .any)["settings.twoFactor.screen"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 8))
        AuthUIFlow.reveal(code, in: app, scroll: form)
        code.tap()
        do { _ = try UIWait.keyboardFrames(in: app, including: [form, code]) } catch { XCTFail("\(error)") }
        AuthUIFlow.reveal(code, in: app, scroll: form)
        code.typeText("123456")
        open("settings.twoFactor.confirm", app: app)
        XCTAssertTrue(app.staticTexts["settings.twoFactor.recoveryCode"].firstMatch.waitForExistence(timeout: 8))
        open("settings.twoFactor.disable", app: app)
        fillSecret("settings.security.prompt.password", "New password1!", app: app)
        open("settings.security.prompt.submit", app: app)
        XCTAssertTrue(app.buttons["settings.twoFactor.enable"].waitForExistence(timeout: 8))
    }

    @MainActor private func fillSecret(_ identifier: String, _ value: String, app: XCUIApplication) {
        let field = app.secureTextFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        AuthUIFlow.reveal(field, in: app)
        field.tap()
        field.typeText(value)
    }

    @MainActor func testPlanShowsStoredCreditsAndNoLinkState() {
        let app = launchSettingsPages()
        defer { app.terminate() }
        open("settings.plan", app: app)
        XCTAssertTrue(app.staticTexts["settings.plan.balance"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["settings.plan.noLink"].exists)
        XCTAssertFalse(app.buttons["Buy credits or a plan"].exists)
    }

    @MainActor func testDeleteAccountKeepsAccountUntilBothConfirmationStepsComplete() {
        let app = launchSettingsPages()
        defer { app.terminate() }
        open("settings.account", app: app)
        open("settings.account.delete", app: app)
        open("settings.delete.keep", app: app)
        XCTAssertTrue(app.buttons["settings.account.delete"].waitForExistence(timeout: 6))
        open("settings.account.delete", app: app)
        open("settings.delete.confirm", app: app)
        fillSecret("settings.delete.password", "wrong", app: app)
        open("settings.delete.submit", app: app)
        XCTAssertTrue(app.staticTexts["settings.delete.error"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["settings.delete.error"].label, "The provided password was incorrect.")
        fillSecret("settings.delete.password", "password", app: app)
        open("settings.delete.submit", app: app)
        XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 12))
    }

    @MainActor private func launchSettingsPages() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            AuthUIFlow.arguments() + ["-cf.settings.language", "system", "-cf.settings.theme", "system"]
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
