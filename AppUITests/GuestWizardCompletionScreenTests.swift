import XCTest

nonisolated final class GuestWizardCompletionScreenTests: ScreenTestCase {
    @MainActor func testFineTuneGuest() {
        let app = GuestWizardScreenUIFlow.launch("WizardFineTuneGuest")
        XCTAssertTrue(app.buttons["wizard.fine-tune.continue"].isHittable)
        XCTAssertTrue(app.buttons["wizard.extra.room.0"].exists)
        XCTAssertFalse(app.switches["wizard.sleep-override"].exists)
        XCTAssertFalse(app.staticTexts["Late check-out"].exists)
        XCTAssertFalse(app.staticTexts["Busy hours before you leave"].exists)
    }

    @MainActor func testReadyGuest() {
        let app = GuestWizardScreenUIFlow.launch("WizardReadyGuest")
        XCTAssertTrue(app.buttons["wizard.ready.sleep"].label.contains("23:30–07:15 · In between"))
        XCTAssertTrue(app.buttons["wizard.ready.questions"].label.contains("2 answered"))
        XCTAssertFalse(app.buttons["wizard.ready.return"].exists)
        let price = app.staticTexts["wizard.ready.guest-price"]
        AuthUIFlow.reveal(price, in: app)
        XCTAssertEqual(price.label, "Paid with 1 of the 3 credits you get when you sign up.")
        app.buttons["wizard.ready.continue"].tap()
        XCTAssertTrue(app.textFields["guest-signup.name"].waitUntil(.exists, timeout: 3))
    }

    @MainActor func testReadyGuestFree() {
        let app = GuestWizardScreenUIFlow.launch("WizardReadyGuestFree")
        let price = app.staticTexts["wizard.ready.guest-price"]
        AuthUIFlow.reveal(price, in: app)
        XCTAssertEqual(price.label, "Your sign-up credits stay unused.")
        XCTAssertTrue(app.buttons["wizard.ready.continue"].isHittable)
    }
}

nonisolated final class GuestWizardDarkDutchScreenTests: ScreenTestCase {
    @MainActor func testReadyGuestDarkNL() {
        let app = GuestWizardScreenUIFlow.launch("WizardReadyGuest", language: "nl", dark: true)
        XCTAssertEqual(app.staticTexts["wizard.title"].label, "Klaar om te plannen")
        XCTAssertTrue(app.buttons["wizard.ready.questions"].label.contains("2 beantwoord"))
        let price = app.staticTexts["wizard.ready.guest-price"]
        AuthUIFlow.reveal(price, in: app)
        XCTAssertEqual(price.label, "Betaald met 1 van de 3 credits die je krijgt als je een account maakt.")
    }
}

nonisolated final class GuestSignupScreenTests: ScreenTestCase {
    @MainActor func testGuestSignupReady() {
        let app = GuestWizardScreenUIFlow.launch("GuestSignup")
        XCTAssertTrue(app.textFields["guest-signup.name"].waitUntil(.exists, timeout: 3))
        XCTAssertFalse(app.staticTexts["auth.banner"].exists)
        let password = app.secureTextFields["guest-signup.password"]
        XCTAssertTrue(password.exists)
        XCTAssertTrue(
            app.staticTexts[
                "Use at least 12 characters, with uppercase and lowercase letters, numbers and symbols. Choose a password that has not appeared in a data leak."
            ].exists)
    }

    @MainActor func testGuestSignupFailed() {
        let app = GuestWizardScreenUIFlow.launch("GuestSignupFailed")
        let banner = app.staticTexts["auth.banner"]
        XCTAssertTrue(banner.waitUntil(.exists, timeout: 3))
        XCTAssertTrue(banner.label.contains("We couldn't create your account."))
        XCTAssertTrue(banner.label.contains("Try again in a moment."))
    }

    @MainActor func testGuestSignupRetry() {
        let app = GuestWizardScreenUIFlow.launch("GuestSignupRetry")
        let banner = app.staticTexts["auth.banner"]
        XCTAssertTrue(banner.waitUntil(.exists, timeout: 3))
        XCTAssertTrue(banner.label.contains("Your account is ready."))
        XCTAssertTrue(banner.label.contains("Try saving again shortly."))
    }

    @MainActor func testGuestSignupReview() {
        let app = GuestWizardScreenUIFlow.launch("GuestSignupReview")
        let review = app.buttons["auth.banner.action"]
        XCTAssertTrue(review.waitUntil(.hittable, timeout: 3))
        review.tap()
        XCTAssertTrue(app.buttons["wizard.ready.continue"].waitUntil(.hittable, timeout: 3))
        XCTAssertFalse(app.textFields["guest-signup.name"].exists)
    }

    @MainActor func testSignInInstead() {
        let app = GuestWizardScreenUIFlow.launch("GuestSignup")
        let signIn = app.buttons["guest-signup.sign-in"]
        XCTAssertTrue(signIn.waitUntil(.exists, timeout: 3))
        AuthUIFlow.reveal(signIn, in: app, scroll: app.scrollViews["guest-signup.scroll"])
        signIn.tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitUntil(.exists, timeout: 3))
    }
}
