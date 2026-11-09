import XCTest

nonisolated final class SignInTests: XCTestCase {
    @MainActor func testWelcomeBackGuestAndAuthLinkSeams() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cf.session", "out", "-cf.reduceMotion"]
        app.launchMeasured()
        defer { app.terminate() }
        openSignIn(app)
        reveal(app.buttons["auth.back"], app)
        app.buttons["auth.back"].tap()
        XCTAssertTrue(app.staticTexts["welcome.wordmark"].waitForMeasuredExistence(timeout: 3))
        openSignIn(app)
        reveal(app.buttons["sign-in.forgot"], app)
        app.buttons["sign-in.forgot"].tap()
        XCTAssertTrue(app.textFields["forgot.email"].waitForMeasuredExistence(timeout: 3))
        AuthUIFlow.reveal(AuthUIFlow.control("auth.back", in: app), in: app)
        AuthUIFlow.control("auth.back", in: app).tap()
        reveal(app.buttons["sign-in.signup"], app)
        app.buttons["sign-in.signup"].tap()
        XCTAssertTrue(app.textFields["sign-up.name"].waitForMeasuredExistence(timeout: 3))
        AuthUIFlow.reveal(AuthUIFlow.control("auth.back", in: app), in: app)
        AuthUIFlow.control("auth.back", in: app).tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitForMeasuredExistence(timeout: 3))
        reveal(app.buttons["sign-in.guest"], app)
        app.buttons["sign-in.guest"].tap()
        XCTAssertTrue(app.staticTexts["route.guestWizard"].waitForMeasuredExistence(timeout: 3))
        XCTAssertFalse(app.images["launch.opening"].exists)
    }
    @MainActor func testReturnChainKeyboardSubmitAndPasswordClearing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cf.session", "out", "-cf.reduceMotion"]
        app.launchMeasured()
        defer { app.terminate() }
        openSignIn(app)
        let email = app.textFields["sign-in.email"]
        reveal(email, app)
        email.tap()
        email.typeText("test@example.com\n")
        let password = app.secureTextFields["sign-in.password"]
        XCTAssertTrue(password.waitForMeasuredExistence(timeout: 3))
        password.typeText("wrong")
        let submit = app.buttons["sign-in.submit"]
        XCTAssertTrue(submit.isHittable)
        let frames = try UIWait.keyboardFrames(in: app, including: [submit])
        XCTAssertLessThanOrEqual(frames[2].maxY, frames[1].minY)
        password.typeText("\n")
        XCTAssertTrue(app.descendants(matching: .any)["auth.banner"].waitForMeasuredExistence(timeout: 5))
        XCTAssertFalse((password.value as? String ?? "").contains("•"))
        XCTAssertEqual(email.value as? String, "test@example.com")
    }
    @MainActor func testMockPasskeyFailureUsesDesignedBannerWithoutSystemPrompt() {
        let app = XCUIApplication()
        app.launchArguments = ["-cf.session", "out", "-cf.reduceMotion"]
        app.launchMeasured()
        defer { app.terminate() }
        openSignIn(app)
        let passkey = app.buttons["sign-in.passkey"]
        reveal(passkey, app)
        passkey.tap()
        XCTAssertTrue(app.descendants(matching: .any)["auth.banner"].waitForMeasuredExistence(timeout: 5))
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertTrue(app.textFields["sign-in.email"].isEnabled)
    }

    @MainActor private func openSignIn(_ app: XCUIApplication) {
        let button = app.buttons["welcome.signIn"]
        XCTAssertTrue(button.waitForMeasuredExistence(timeout: 6))
        reveal(button, app)
        button.tap()
        XCTAssertTrue(app.staticTexts["auth.heading"].waitForMeasuredExistence(timeout: 3))
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        let scroll =
            element.identifier == "welcome.signIn"
            ? app.scrollViews.containing(.button, identifier: "welcome.signIn").element : AuthUIFlow.scroll(in: app)
        AuthUIFlow.reveal(element, in: app, scroll: scroll)
    }
}
