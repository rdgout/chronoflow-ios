import XCTest

nonisolated final class TripWizardActionsScreenTests: ScreenTestCase {
    @MainActor func testUntouchedEditHasDisabledUpdateButton() {
        let app = WizardScreenUIFlow.launch("WizardEdit", language: "nl")
        XCTAssertTrue(app.buttons["wizard.ready.continue"].waitUntil(.hittable, timeout: 3))
        XCTAssertFalse(app.buttons["wizard.ready.continue"].isEnabled)
        XCTAssertEqual(app.staticTexts["wizard.title"].firstMatch.label, "Je reis bewerken")
    }

    @MainActor func testDuplicateOpensOutboundWithEmptyDates() {
        let app = WizardScreenUIFlow.launch("WizardDuplicate", language: "nl")
        XCTAssertTrue(app.buttons["wizard.outbound.continue"].waitUntil(.hittable, timeout: 3))
        XCTAssertFalse(app.buttons["wizard.outbound.continue"].isEnabled)
        XCTAssertTrue(app.buttons["wizard.0.departure.date-time"].exists)
    }

    @MainActor func testEditNoCreditsHasCloseWithoutBilling() {
        let app = WizardScreenUIFlow.launch("WizardEditReturnNoCredits", language: "nl")
        XCTAssertTrue(app.buttons["wizard.ready.no-credits"].waitUntil(.hittable, timeout: 3))
        XCTAssertFalse(app.buttons["wizard.ready.continue"].exists)
    }

    @MainActor func testEditDiscardUsesNativeAlert() {
        let app = WizardScreenUIFlow.launch("WizardDiscardEdit", language: "nl")
        XCTAssertTrue(app.alerts.firstMatch.waitUntil(.exists, timeout: 3))
        XCTAssertTrue(app.buttons["Wijzigingen verwijderen"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Verder bewerken"].firstMatch.exists)
    }
}

nonisolated final class TripActionsScreenTests: ScreenTestCase {
    @MainActor func testEditOpensMemberWizardFromActions() {
        let app = launchActions()
        app.buttons["trip.actions.edit"].tap()
        XCTAssertTrue(app.staticTexts["wizard.title"].firstMatch.waitUntil(.exists, timeout: 4))
        XCTAssertTrue(app.buttons["wizard.close"].exists)
    }

    @MainActor func testDuplicateOpensOutboundFromActions() {
        let app = launchActions()
        app.buttons["trip.actions.duplicate"].tap()
        XCTAssertTrue(app.buttons["wizard.outbound.continue"].waitUntil(.hittable, timeout: 4))
        XCTAssertFalse(app.buttons["wizard.outbound.continue"].isEnabled)
    }

    @MainActor private func launchActions() -> XCUIApplication {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments = AuthUIFlow.arguments()
        AuthUIFlow.launchSignedIn(
            app, walkthroughSeen: true,
            extraEnv: [
                "CF_WIZARD_BOARD_CAPTURE": "TripActions", "CF_PLAN_TEST_ROUTE": "trip:\(PlanUIFlow.tripID)",
            ])
        XCTAssertTrue(app.buttons["trip.actions.edit"].waitUntil(.hittable, timeout: 4))
        return app
    }
}
