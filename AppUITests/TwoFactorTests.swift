import XCTest

nonisolated final class TwoFactorTests: XCTestCase {
    @MainActor func testNumberPadDoesNotAutoSubmitAndVerifyCompletesTheMockSession() throws {
        let app = launchTwoFactorApp()
        defer { app.terminate() }
        try openMockTwoFactor(app)
        let code = app.textFields["two-factor.code"]
        code.tap()
        code.typeText("1234567")
        XCTAssertEqual(code.value as? String, "123456")
        XCTAssertFalse(app.staticTexts["route.walkthrough"].exists)
        let submit = app.buttons["two-factor.submit"]
        try assertTwoFactorKeyboardPair(code, app: app)
        XCTAssertFalse(app.keyboards.buttons["Go"].exists)
        submit.tap()
        XCTAssertTrue(app.staticTexts["route.walkthrough"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["two-factor.code"].exists)
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor func testModeToggleClearsCodeAndRecoveryReturnCompletesTheMockSession() throws {
        let app = launchTwoFactorApp()
        defer { app.terminate() }
        try openMockTwoFactor(app)
        let code = app.textFields["two-factor.code"]
        code.tap()
        code.typeText("123")
        revealTwoFactor(app.buttons["two-factor.toggle"], in: app.scrollViews["auth.scroll"])
        app.buttons["two-factor.toggle"].tap()
        let recovery = app.textFields["two-factor.recovery_code"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 3))
        XCTAssertEqual(recovery.value as? String, "")
        recovery.tap()
        recovery.typeText("AbCdEf1234-GhIjKl5678")
        try assertTwoFactorKeyboardPair(recovery, app: app)
        recovery.typeText("\n")
        XCTAssertTrue(app.staticTexts["route.walkthrough"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor func testInteractiveKeyboardDismissAndBackDiscardTheChallengeAndCode() throws {
        let app = launchTwoFactorApp()
        defer { app.terminate() }
        try openMockTwoFactor(app)
        let code = app.textFields["two-factor.code"]
        code.tap()
        code.typeText("123")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let scroll = app.scrollViews["auth.scroll"]
        XCTAssertEqual(app.scrollViews.matching(identifier: "auth.scroll").count, 1)
        XCTAssertTrue(scroll.isHittable)
        let window = app.windows.firstMatch
        let frames = try UIWait.stableFrames([window, scroll, app.keyboards.firstMatch], timeout: 10)
        let viewport = frames[0].intersection(frames[1])
        let contentAboveKeyboard = viewport.intersection(
            CGRect(
                x: viewport.minX, y: viewport.minY, width: viewport.width,
                height: max(0, min(viewport.maxY, frames[2].minY) - viewport.minY)))
        XCTAssertFalse(contentAboveKeyboard.isEmpty)
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(
            CGVector(dx: contentAboveKeyboard.midX - frames[0].minX, dy: contentAboveKeyboard.midY - frames[0].minY))
        // Duo's keyboard can sit below the app window; the drag must reach it in screen coordinates.
        let end = origin.withOffset(
            CGVector(
                dx: contentAboveKeyboard.midX - frames[0].minX,
                dy: max(frames[0].maxY, frames[2].maxY) - frames[0].minY - 1))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !app.keyboards.firstMatch.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertEqual(code.value as? String, "123")
        revealTwoFactor(app.buttons["auth.back"], in: scroll)
        app.buttons["auth.back"].tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.secureTextFields["sign-in.password"].value as? String, "")
        try openMockTwoFactor(app, fromSignIn: true)
        XCTAssertEqual(app.textFields["two-factor.code"].value as? String, "")
        XCTAssertFalse(app.images["launch.opening"].exists)
    }
}

@MainActor func launchTwoFactorApp(language: String = "en", xxLarge: Bool = false, server: Bool = false)
    -> XCUIApplication
{
    let app = XCUIApplication()
    app.launchArguments = [
        "-cf.session", "out", "-cf.reduceMotion", "-cf.isolatedMockServer", "-AppleLanguages", "(\(language))",
        "-AppleLocale",
        language == "nl" ? "nl_NL" : "en_US",
    ]
    if xxLarge { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"] }
    if server { app.launchArguments += ["-cf.twoFactorServerFailure"] }
    app.launch()
    return app
}

@MainActor func openMockTwoFactor(_ app: XCUIApplication, fromSignIn: Bool = false) throws {
    if !fromSignIn {
        let signIn = app.buttons["welcome.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 6))
        revealTwoFactor(signIn, in: app.scrollViews.firstMatch)
        signIn.tap()
    }
    let email = app.textFields["sign-in.email"]
    XCTAssertTrue(email.waitForExistence(timeout: 3))
    revealTwoFactor(email, in: app.scrollViews["auth.scroll"])
    email.tap()
    if !fromSignIn { email.typeText("twofactor@example.com") }
    email.typeText("\n")
    app.secureTextFields["sign-in.password"].typeText("password\n")
    XCTAssertTrue(app.textFields["two-factor.code"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["route.walkthrough"].exists)
    revealTwoFactor(app.textFields["two-factor.code"], in: app.scrollViews["auth.scroll"])
}

@MainActor func revealTwoFactor(_ element: XCUIElement, in scroll: XCUIElement) {
    for _ in 0..<8 where !element.isHittable {
        if element.frame.midY < scroll.frame.minY { scroll.swipeDown() } else { scroll.swipeUp() }
    }
    XCTAssertTrue(element.isHittable)
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
    let focused = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in field.value(forKey: "hasKeyboardFocus") as? Bool == true }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed, "\(context): focus")
    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "\(context): requires software keyboard")
    let submit = app.buttons["two-factor.submit"]
    let frames = try UIWait.stableFrames(
        [app.windows.firstMatch, app.scrollViews["auth.scroll"], keyboard, field, submit], timeout: 10)
    let viewport = frames[0].intersection(frames[1])
    let safeViewport =
        frames[2].intersection(frames[0]).isEmpty
        ? frames[0]
        : viewport.intersection(
            CGRect(
                x: viewport.minX, y: viewport.minY, width: viewport.width,
                height: max(0, frames[2].minY - viewport.minY)))
    let message = """
        Two-factor keyboard [\(context), focus=\(field.identifier)]
        window=\(frames[0]) scroll=\(frames[1]) keyboard=\(frames[2])
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
