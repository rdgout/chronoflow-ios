import XCTest

nonisolated final class ForgotPasswordKeyboardTests: XCTestCase {
    @MainActor func testEnglishFieldErrorAtXXLarge() throws { try check(language: "en") }
    @MainActor func testDutchFieldErrorAtXXLarge() throws { try check(language: "nl") }
    @MainActor func testEnglishServerAtXXLarge() throws { try check(language: "en", failure: "server") }
    @MainActor func testDutchServerAtXXLarge() throws { try check(language: "nl", failure: "server") }
    @MainActor func testEnglishThrottleAtXXLarge() throws { try check(language: "en", failure: "throttle") }
    @MainActor func testDutchThrottleAtXXLarge() throws { try check(language: "nl", failure: "throttle") }

    @MainActor private func check(language: String, failure: String? = nil) throws {
        let app = launchForgotApp(language: language, xxLarge: true, failure: failure)
        defer { app.terminate() }
        openForgot(app)
        let field = app.textFields["forgot.email"]
        field.tap()
        field.typeText(failure == nil ? "invalid" : "retained@example.com")
        try assertPair(field, app: app, context: "\(language), initial")
        AuthUIFlow.control("forgot.submit", in: app).tap()
        if failure != nil {
            XCTAssertTrue(AuthUIFlow.control("auth.banner", in: app).waitForExistence(timeout: 5))
        } else {
            let received = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    field.isEnabled && field.value(forKey: "hasKeyboardFocus") as? Bool == true
                }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 5), .completed)
            XCTAssertFalse(AuthUIFlow.control("auth.banner", in: app).exists)
            XCTAssertFalse(AuthUIFlow.control("forgot.notice", in: app).exists)
        }
        try assertPair(field, app: app, context: "\(language), \(failure ?? "field error")")
        let scroll = AuthUIFlow.scroll(in: app)
        let frames = try UIWait.keyboardFrames(in: app, including: [scroll])
        let viewport = AuthUIFlow.viewport(in: app, scrollFrame: frames[2])
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.2))
        let end = origin.withOffset(
            CGVector(dx: viewport.midX, dy: min(frames[0].maxY - 1, frames[1].minY + frames[1].height * 0.8)))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !app.keyboards.firstMatch.exists
                    || !SoftwareKeyboardVisibility.isVisible(
                        app.keyboards.firstMatch.frame, in: app.windows.firstMatch.frame)
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed, "Interactive keyboard dismiss")
    }

    @MainActor private func assertPair(_ field: XCUIElement, app: XCUIApplication, context: String) throws {
        defer {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Forgot keyboard \(context)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in field.value(forKey: "hasKeyboardFocus") as? Bool == true }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed, context)
        let submit = AuthUIFlow.control("forgot.submit", in: app)
        let frames = try UIWait.keyboardFrames(in: app, including: [AuthUIFlow.scroll(in: app), field, submit])
        let viewport = AuthUIFlow.viewport(in: app, scrollFrame: frames[2])
        let message =
            "Forgot keyboard [\(context)] window=\(frames[0]) keyboard=\(frames[1]) viewport=\(viewport) field=\(frames[3]) submit=\(frames[4])"
        let attachment = XCTAttachment(string: message)
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(viewport.isEmpty, message)
        XCTAssertTrue(viewport.contains(frames[3]), message)
        XCTAssertTrue(viewport.contains(frames[4]), message)
        XCTAssertTrue(field.isHittable && submit.isHittable, message)
    }
}
