import XCTest

nonisolated final class TwoFactorKeyboardTests: XCTestCase {
    @MainActor func testEnglishCodeFieldErrorAtXXLarge() throws {
        try check(language: "en", recovery: false, server: false)
    }
    @MainActor func testDutchCodeFieldErrorAtXXLarge() throws {
        try check(language: "nl", recovery: false, server: false)
    }
    @MainActor func testEnglishRecoveryFieldErrorAtXXLarge() throws {
        try check(language: "en", recovery: true, server: false)
    }
    @MainActor func testDutchRecoveryFieldErrorAtXXLarge() throws {
        try check(language: "nl", recovery: true, server: false)
    }
    @MainActor func testEnglishCodeServerAtXXLarge() throws { try check(language: "en", recovery: false, server: true) }
    @MainActor func testDutchCodeServerAtXXLarge() throws { try check(language: "nl", recovery: false, server: true) }
    @MainActor func testEnglishRecoveryServerAtXXLarge() throws {
        try check(language: "en", recovery: true, server: true)
    }
    @MainActor func testDutchRecoveryServerAtXXLarge() throws {
        try check(language: "nl", recovery: true, server: true)
    }

    @MainActor private func check(language: String, recovery: Bool, server: Bool) throws {
        let app = launchTwoFactorApp(language: language, xxLarge: true, server: server)
        defer { app.terminate() }
        try openMockTwoFactor(app)
        let scroll = app.scrollViews["auth.scroll"]
        if recovery {
            revealTwoFactor(app.buttons["two-factor.toggle"], in: scroll)
            app.buttons["two-factor.toggle"].tap()
        }
        let field = app.textFields[recovery ? "two-factor.recovery_code" : "two-factor.code"]
        field.tap()
        field.typeText(recovery ? " " : "1")
        try assertTwoFactorKeyboardPair(field, app: app, context: "\(language), xxLarge, initial", attach: add)
        app.buttons["two-factor.submit"].tap()
        if server {
            XCTAssertTrue(app.descendants(matching: .any)["auth.banner"].waitForExistence(timeout: 5))
        } else {
            let received = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in field.value as? String == "" && field.isEnabled }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 5), .completed)
            XCTAssertFalse(app.descendants(matching: .any)["auth.banner"].exists)
        }
        try assertTwoFactorKeyboardPair(
            field, app: app,
            context: "\(language), xxLarge, \(recovery ? "recovery" : "code"), \(server ? "server" : "field error")",
            attach: add)
        XCTAssertEqual(field.value as? String, "")
        XCTAssertTrue(field.isEnabled)
        XCTAssertEqual(app.descendants(matching: .any)["auth.banner"].exists, server)
    }
}
