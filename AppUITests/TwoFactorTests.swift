import XCTest

nonisolated final class TwoFactorTests: ScreenTestCase {
    @MainActor func testNumberPadDoesNotAutoSubmitAndVerifyCompletesTheMockSession() throws {
        let app = launchTwoFactorApp()
        try openMockTwoFactor(app)
        let code = app.textFields["two-factor.code"]
        code.tap()
        code.typeText("1234567")
        XCTAssertEqual(code.value as? String, "123456")
        XCTAssertFalse(app.staticTexts["walkthrough.title"].exists)
        let submit = app.buttons["two-factor.submit"]
        try assertTwoFactorKeyboardPair(code, app: app)
        XCTAssertFalse(app.keyboards.buttons["Go"].exists)
        submit.tap()
        XCTAssertTrue(app.staticTexts["walkthrough.title"].waitUntil(.exists, timeout: 10))
        XCTAssertFalse(app.textFields["two-factor.code"].exists)
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor func testModeToggleClearsCodeAndRecoveryReturnCompletesTheMockSession() throws {
        let app = launchTwoFactorApp()
        try openMockTwoFactor(app)
        let code = app.textFields["two-factor.code"]
        code.tap()
        code.typeText("123")
        revealTwoFactor(
            app.buttons["two-factor.toggle"], app: app, in: AuthUIFlow.scroll(in: app, identifier: "two-factor.scroll"))
        app.buttons["two-factor.toggle"].tap()
        let recovery = app.textFields["two-factor.recovery_code"]
        XCTAssertTrue(recovery.waitUntil(.exists, timeout: 3))
        XCTAssertEqual(recovery.value as? String, "")
        XCTAssertEqual(recovery.placeholderValue, "xxxx-xxxx")
        XCTAssertEqual(recovery.label, "Recovery code")
        recovery.tap()
        recovery.typeText("AbCdEf1234-GhIjKl5678")
        XCTAssertEqual(recovery.value as? String, "AbCdEf1234-GhIjKl5678")
        try assertTwoFactorKeyboardPair(recovery, app: app)
        recovery.typeText("\n")
        XCTAssertTrue(app.staticTexts["walkthrough.title"].waitUntil(.exists, timeout: 10))
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor func testInteractiveKeyboardDismissAndBackDiscardTheChallengeAndCode() throws {
        let app = launchTwoFactorApp()
        try openMockTwoFactor(app)
        let code = app.textFields["two-factor.code"]
        code.tap()
        code.typeText("123")
        let scroll = AuthUIFlow.scroll(in: app, identifier: "two-factor.scroll")
        XCTAssertEqual(app.scrollViews.matching(identifier: "two-factor.scroll").count, 1)
        XCTAssertTrue(scroll.isHittable)
        let window = app.windows.firstMatch
        let frames = try UIWait.keyboardFrames(in: app, including: [scroll])
        let viewport = AuthUIFlow.viewport(in: app, scrollFrame: frames[2])
        let contentAboveKeyboard = viewport.intersection(
            CGRect(
                x: viewport.minX, y: viewport.minY, width: viewport.width,
                height: max(0, min(viewport.maxY, frames[1].minY) - viewport.minY)))
        XCTAssertFalse(contentAboveKeyboard.isEmpty)
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(
            CGVector(dx: contentAboveKeyboard.midX - frames[0].minX, dy: contentAboveKeyboard.midY - frames[0].minY))
        let end = origin.withOffset(
            CGVector(
                dx: contentAboveKeyboard.midX - frames[0].minX,
                dy: max(frames[0].maxY, frames[1].maxY) - frames[0].minY - 1))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        let dismissed = { () -> Bool in
            !app.keyboards.firstMatch.exists
        }
        XCTAssertTrue(UIWait.until(timeout: 5, condition: dismissed))
        XCTAssertEqual(code.value as? String, "123")
        revealTwoFactor(AuthUIFlow.control("auth.back", in: app), app: app, in: scroll)
        AuthUIFlow.control("auth.back", in: app).tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitUntil(.exists, timeout: 3))
        XCTAssertEqual(app.secureTextFields["sign-in.password"].value as? String, "")
        try openMockTwoFactor(app, fromSignIn: true)
        XCTAssertEqual(app.textFields["two-factor.code"].value as? String, "")
        XCTAssertFalse(app.images["launch.opening"].exists)
    }
}

@MainActor func launchTwoFactorApp(language: String = "en", xxLarge: Bool = false, server: Bool = false)
    -> XCUIApplication
{
    AuthUIFlow.launchScreen(
        "two-factor", language: language, xxLarge: xxLarge,
        extraArguments: server ? ["-cf.twoFactorServerFailure"] : [])
}

@MainActor func openMockTwoFactor(_ app: XCUIApplication, fromSignIn: Bool = false) throws {
    if fromSignIn {
        AuthUIFlow.signIn(app, email: MockScenarioValues.twoFactorEmail)
        XCTAssertTrue(app.textFields["two-factor.code"].waitUntil(.exists, timeout: 5))
    } else {
        AuthUIFlow.requireSeededScreen("two-factor", in: app)
    }
}

@MainActor func revealTwoFactor(_ element: XCUIElement, app: XCUIApplication, in scroll: XCUIElement) {
    AuthUIFlow.reveal(element, in: app, scroll: scroll)
}

@MainActor func assertTwoFactorKeyboardPair(
    _ field: XCUIElement, app: XCUIApplication, context: String = "number pad",
    attach: (XCTAttachment) -> Void = { _ in }
) throws {
    defer {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Two-factor \(context), \(field.identifier)"
        screenshot.lifetime = .keepAlways
        attach(screenshot)
    }
    let focused = { () -> Bool in
        field.value(forKey: "hasKeyboardFocus") as? Bool == true
    }
    XCTAssertTrue(UIWait.until(timeout: 5, condition: focused), "\(context): focus")
    let submit = app.buttons["two-factor.submit"]
    let frames = try UIWait.keyboardFrames(
        in: app, including: [AuthUIFlow.scroll(in: app, identifier: "two-factor.scroll"), field, submit])
    let viewport = AuthUIFlow.viewport(in: app, scrollFrame: frames[2])
    let safeViewport = viewport.intersection(
        CGRect(
            x: viewport.minX, y: viewport.minY, width: viewport.width,
            height: max(0, frames[1].minY - viewport.minY)))
    let message = """
        Two-factor keyboard [\(context), focus=\(field.identifier)]
        window=\(frames[0]) scroll=\(frames[2]) keyboard=\(frames[1])
        keyboardSafeViewport=\(safeViewport) field=\(frames[3]) submit=\(frames[4])
        """
    print(message)
    let geometry = XCTAttachment(string: message)
    geometry.lifetime = .keepAlways
    attach(geometry)
    XCTAssertFalse(safeViewport.isEmpty, message)
    XCTAssertTrue(safeViewport.contains(frames[3]), "Focused input must be fully visible. \(message)")
    XCTAssertTrue(safeViewport.contains(frames[4]), "Verify must be fully visible. \(message)")
    XCTAssertTrue(field.isHittable, message)
    XCTAssertTrue(submit.isHittable, message)
}
