import XCTest

nonisolated final class GuestWizardJourneyTests: ScreenTestCase {
    @MainActor func testWelcomeThroughSignupOpensClaimedTrip() {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment = [
            "CF_GUEST_WIZARD_JOURNEY": "1", "CF_WIZARD_BOARD_CAPTURE": "WizardGuestJourney",
        ]
        app.launchMeasured()
        tap("welcome.plan", in: app)
        tap("wizard.where.continue", in: app)
        tap("wizard.outbound.continue", in: app)
        XCTAssertTrue(app.datePickers["wizard.sleep.habitual_bed"].exists)
        tap("wizard.sleep.continue", in: app)
        XCTAssertTrue(app.otherElements["wizard.checking.line.1"].waitUntil(.exists, timeout: 2))
        tap("wizard.choice.question.18_64", in: app)
        tap("wizard.fine-tune.continue", in: app)
        tap("wizard.ready.continue", in: app)
        XCTAssertTrue(app.textFields["guest-signup.name"].waitUntil(.exists, timeout: 2))
        let submit = app.buttons["guest-signup.submit"]
        AuthUIFlow.reveal(submit, in: app, scroll: app.scrollViews["guest-signup.scroll"])
        tap("guest-signup.submit", in: app)
        tap("verify.open-email", in: app)
        tap("walkthrough.skip", in: app)
        XCTAssertTrue(app.scrollViews["trip.scroll"].waitUntil(.exists, timeout: 3))
        XCTAssertFalse(app.buttons["wizard.ready.continue"].exists)
    }

    @MainActor private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier].firstMatch
        guard button.waitUntil(.hittable, timeout: 5) else {
            XCTFail("Expected \(identifier)")
            return
        }
        button.tap()
    }
}
