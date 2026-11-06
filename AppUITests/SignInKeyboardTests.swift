import XCTest

nonisolated final class SignInKeyboardTests: XCTestCase {
    private enum Failure { case email, password, server }

    @MainActor func testEnglishEmailErrorAtXXLarge() throws {
        try assertKeyboardLayout(language: "en", failure: .email)
    }
    @MainActor func testDutchEmailErrorAtXXLarge() throws {
        try assertKeyboardLayout(language: "nl", failure: .email)
    }
    @MainActor func testEnglishPasswordErrorAtXXLarge() throws {
        try assertKeyboardLayout(language: "en", failure: .password)
    }
    @MainActor func testDutchPasswordErrorAtXXLarge() throws {
        try assertKeyboardLayout(language: "nl", failure: .password)
    }
    @MainActor func testEnglishServerBannerAtXXLarge() throws {
        try assertKeyboardLayout(language: "en", failure: .server)
    }
    @MainActor func testDutchServerBannerAtXXLarge() throws {
        try assertKeyboardLayout(language: "nl", failure: .server)
    }

    @MainActor private func assertKeyboardLayout(language: String, failure: Failure) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-cf.session", "out", "-cf.reduceMotion", "-AppleLanguages", "(\(language))", "-AppleLocale",
            language == "nl" ? "nl_NL" : "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL",
        ]
        app.launch()
        defer { app.terminate() }
        let signIn = app.buttons["welcome.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 6))
        reveal(signIn, in: app.scrollViews.firstMatch)
        signIn.tap()
        XCTAssertTrue(app.staticTexts["auth.heading"].waitForExistence(timeout: 3))

        let scroll = app.scrollViews["auth.scroll"]
        let email = app.textFields["sign-in.email"]
        let password = app.secureTextFields["sign-in.password"]
        let submit = app.buttons["sign-in.submit"]
        switch failure {
        case .email:
            reveal(submit, in: scroll)
            submit.tap()
        case .password:
            reveal(email, in: scroll)
            email.tap()
            email.typeText("keyboard@example.com")
            reveal(submit, in: scroll)
            submit.tap()
        case .server:
            let passkey = app.buttons["sign-in.passkey"]
            reveal(passkey, in: scroll)
            passkey.tap()
            XCTAssertTrue(app.descendants(matching: .any)["auth.banner"].waitForExistence(timeout: 5))
            reveal(email, in: scroll)
            email.tap()
        }

        let context = "\(language), xxLarge, \(failure)"
        if failure == .password {
            try assertVisiblePair(field: password, app: app, context: context)
            reveal(email, in: scroll)
            email.tap()
            try assertVisiblePair(field: email, app: app, context: context)
        } else {
            try assertVisiblePair(field: email, app: app, context: context)
            email.typeText("\n")
            try assertVisiblePair(field: password, app: app, context: context)
        }
    }

    @MainActor private func assertVisiblePair(field: XCUIElement, app: XCUIApplication, context: String) throws {
        defer {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(context), \(field.identifier)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        let keyboard = app.keyboards.firstMatch
        // Inspect keyboard focus without editing away the error state.
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in field.value(forKey: "hasKeyboardFocus") as? Bool == true }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed, "\(context): \(field.identifier) focus")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "\(context): requires the software keyboard")
        let submit = app.buttons["sign-in.submit"]
        let frames = try UIWait.stableFrames(
            [app.windows.firstMatch, app.scrollViews["auth.scroll"], keyboard, field, submit], timeout: 10)
        let viewport = frames[0].intersection(frames[1])
        let keyboardFrame = frames[2]
        let safeViewport = viewport.intersection(
            CGRect(
                x: viewport.minX, y: viewport.minY, width: viewport.width,
                height: max(0, keyboardFrame.minY - viewport.minY)))
        let message = """
            Sign in keyboard [\(context), focus=\(field.identifier)]
            window=\(frames[0]) scroll=\(frames[1]) keyboard=\(keyboardFrame)
            keyboardSafeViewport=\(safeViewport) field=\(frames[3]) submit=\(frames[4])
            """
        print(message)
        let geometry = XCTAttachment(string: message)
        geometry.lifetime = .keepAlways
        add(geometry)

        XCTAssertFalse(keyboardFrame.intersection(frames[0]).isEmpty, message)
        XCTAssertFalse(safeViewport.isEmpty, message)
        XCTAssertTrue(safeViewport.contains(frames[3]), "Focused input must be fully visible. \(message)")
        XCTAssertTrue(safeViewport.contains(frames[4]), "Submit must be fully visible. \(message)")
        XCTAssertTrue(field.isHittable, message)
        XCTAssertTrue(submit.isHittable, message)
    }

    @MainActor private func reveal(_ element: XCUIElement, in scroll: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            if element.frame.midY < scroll.frame.minY {
                scroll.swipeDown()
            } else {
                scroll.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable)
    }
}
