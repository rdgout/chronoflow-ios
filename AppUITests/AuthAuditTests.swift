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
            let message = """
                Auth accessibility [\(language), \(appearance), \(stage)] \
                auditType=\(issue.auditType) identifier=\(issue.element?.identifier ?? "<nil>") \
                label=\(issue.element?.label ?? "<nil>") compactDescription=\(issue.compactDescription)
                """
            print(message)
            let attachment = XCTAttachment(string: message)
            attachment.lifetime = .keepAlways
            self.add(attachment)
            XCTFail(message)
            return false
        }
    }
}
