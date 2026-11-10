import XCTest

@MainActor enum GuestWizardScreenUIFlow {
    static func launch(_ board: String, language: String = "en", dark: Bool = false) -> XCUIApplication {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments = AuthUIFlow.arguments(language: language)
        if dark { app.launchArguments += ["-cf.settings.theme", "dark"] }
        app.launchEnvironment = ["CF_GUEST_WIZARD": "1", "CF_WIZARD_BOARD_CAPTURE": board]
        app.launchMeasured()
        XCTAssertTrue(app.staticTexts["wizard.title"].firstMatch.waitUntil(.exists, timeout: 5))
        return app
    }
}

nonisolated final class GuestWizardScreenTests: ScreenTestCase {
    @MainActor func testWhereGuest() {
        let app = GuestWizardScreenUIFlow.launch("WizardWhereGuest")
        XCTAssertTrue(app.buttons["wizard.from"].label.contains("AMS"))
        XCTAssertFalse(app.staticTexts["From your last trip"].exists)
        XCTAssertTrue(app.buttons["wizard.where.continue"].isEnabled)
    }

    @MainActor func testOutboundPastGuest() {
        let app = GuestWizardScreenUIFlow.launch("WizardOutboundPastGuest")
        XCTAssertEqual(
            app.staticTexts["wizard.outbound.past"].label,
            "A new plan needs an upcoming arrival. Check your flight dates.")
        XCTAssertTrue(app.buttons["wizard.0.departure.date-time"].isHittable)
    }

    @MainActor func testSleepGuest() {
        let app = GuestWizardScreenUIFlow.launch("WizardSleep")
        XCTAssertTrue(app.staticTexts["On a normal work day."].exists)
        XCTAssertTrue(app.datePickers["wizard.sleep.habitual_bed"].exists)
        XCTAssertTrue(app.buttons["wizard.sleep.continue"].isHittable)
    }

    @MainActor func testCheckingGuest() {
        let app = GuestWizardScreenUIFlow.launch("WizardCheckingGuest")
        XCTAssertTrue(app.otherElements["wizard.checking.line.1"].label.contains("Your answers"))
        XCTAssertFalse(app.staticTexts["Your saved answers"].exists)
    }

    @MainActor func testAgeGuest() {
        let app = GuestWizardScreenUIFlow.launch("WizardQAge")
        XCTAssertTrue(app.buttons["wizard.choice.question.under_18"].isHittable)
        let disclaimer = app.staticTexts["wizard.question.disclaimer"]
        AuthUIFlow.reveal(disclaimer, in: app)
        XCTAssertEqual(
            disclaimer.label,
            "ChronoFlow gives timing guidance, not medical advice. If you're unsure about a question, check with your doctor."
        )
    }

    @MainActor func testExcludedGuest() {
        let app = GuestWizardScreenUIFlow.launch("WizardExcluded")
        XCTAssertTrue(app.buttons["wizard.excluded.continue"].isHittable)
        app.buttons["wizard.excluded.secondary-close"].tap()
        XCTAssertTrue(app.buttons["welcome.plan"].waitUntil(.exists, timeout: 3))
    }

    @MainActor func testDiscardGuest() {
        let app = GuestWizardScreenUIFlow.launch("WizardDiscardGuest")
        app.buttons["wizard.close"].tap()
        let alert = app.alerts["Discard this trip?"]
        XCTAssertTrue(alert.waitUntil(.exists, timeout: 3))
        XCTAssertTrue(alert.staticTexts["What you entered is not saved. You go back to the welcome screen."].exists)
        alert.buttons["Keep editing"].tap()
        XCTAssertTrue(app.buttons["wizard.outbound.continue"].isHittable)
    }

    @MainActor func testEmptyWhereClosesImmediately() {
        let app = GuestWizardScreenUIFlow.launch("WizardWhereGuestEmpty")
        app.buttons["wizard.close"].tap()
        XCTAssertTrue(app.buttons["welcome.plan"].waitUntil(.exists, timeout: 3))
        XCTAssertFalse(app.alerts["Discard this trip?"].exists)
    }
}
