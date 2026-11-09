import XCTest

nonisolated final class AuthAuditTests: XCTestCase {
    @MainActor func testSignInAuditInBothLanguagesAndAppearances() async throws {
        let device = XCUIDevice.shared
        let previous = device.appearance
        defer { device.appearance = previous }
        for language in ["en", "nl"] {
            for appearance in [XCUIDevice.Appearance.light, .dark] {
                try DeviceAppearance.set(appearance)
                let app = XCUIApplication()
                app.launchArguments = [
                    "-cf.session", "out", "-cf.reduceMotion", "-AppleLanguages", "(\(language))", "-AppleLocale",
                    language == "nl" ? "nl_NL" : "en_US",
                ]
                app.launch()
                defer { app.terminate() }
                let signIn = app.buttons["welcome.signIn"]
                XCTAssertTrue(signIn.waitForExistence(timeout: 6))
                for _ in 0..<8 where !signIn.isHittable { app.scrollViews.firstMatch.swipeUp() }
                signIn.tap()
                XCTAssertTrue(app.staticTexts["auth.heading"].waitForExistence(timeout: 3))
                try audit(app, language: language, appearance: appearance, stage: "initial")
                for id in ["sign-in.passkey", "sign-in.submit", "sign-in.forgot", "sign-in.signup", "sign-in.guest"] {
                    let button = app.buttons[id]
                    for _ in 0..<8 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
                    XCTAssertTrue(button.isHittable)
                    try audit(app, language: language, appearance: appearance, stage: id)
                }
            }
        }
    }

    @MainActor private func audit(
        _ app: XCUIApplication, language: String, appearance: XCUIDevice.Appearance, stage: String
    ) throws {
        try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType)) { issue in
            let boardContrast = Self.isBoardContrast(identifier: issue.element?.identifier, auditType: issue.auditType)
            let message = """
                Auth accessibility [\(language), \(appearance), \(stage)] \
                auditType=\(issue.auditType) identifier=\(issue.element?.identifier ?? "<nil>") \
                label=\(issue.element?.label ?? "<nil>") compactDescription=\(issue.compactDescription) \
                boardContrast=\(boardContrast) ignored=\(boardContrast)
                """
            print(message)
            let attachment = XCTAttachment(string: message)
            attachment.lifetime = .keepAlways
            self.add(attachment)
            if !boardContrast { XCTFail(message) }
            return boardContrast
        }
    }

    @MainActor private static func isBoardContrast(identifier: String?, auditType: XCUIAccessibilityAuditType) -> Bool {
        // Board boundary contrast is accepted, OQ 33 (user 2026-11-06); text ratios remain pinned.
        auditType == .contrast && identifier == "sign-in.guest"
    }

    @MainActor func testAuditAllowsOnlyTheGuestFooterBoardContrastPair() {
        XCTAssertTrue(Self.isBoardContrast(identifier: "sign-in.guest", auditType: .contrast))
        for type: XCUIAccessibilityAuditType in [
            .textClipped, .dynamicType, .hitRegion, .trait, .all, [.contrast, .textClipped],
        ] {
            XCTAssertFalse(Self.isBoardContrast(identifier: "sign-in.guest", auditType: type))
        }
        for identifier in [
            nil, "", "sign-in", "sign-in.submit", "sign-in.passkey", "sign-in.email", "sign-in.password",
            "sign-in.forgot", "sign-in.signup", "auth.heading", "auth.banner", "welcome.plan", "sign-in.guest.new",
        ] {
            XCTAssertFalse(Self.isBoardContrast(identifier: identifier, auditType: .contrast))
        }
    }
}
