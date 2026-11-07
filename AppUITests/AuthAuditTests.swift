import XCTest

nonisolated final class AuthAuditTests: XCTestCase {
    @MainActor func testSignInAndBothTwoFactorModesInBothLanguagesAppearancesAndSizes() async throws {
        let device = XCUIDevice.shared
        let previous = device.appearance
        defer { device.appearance = previous }
        for language in ["en", "nl"] {
            for appearance in [XCUIDevice.Appearance.light, .dark] {
                for xxLarge in [false, true] {
                    try DeviceAppearance.set(appearance)
                    let app = XCUIApplication()
                    app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
                    app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
                    app.launch()
                    defer { app.terminate() }
                    AuthUIFlow.openSignIn(app)
                    let context = "\(language), \(xxLarge ? "xxLarge" : "default")"
                    auditControls(
                        app,
                        identifiers: [
                            "auth.back", "sign-in.passkey", "sign-in.email", "sign-in.password",
                            "sign-in.submit", "sign-in.forgot", "sign-in.signup", "sign-in.guest",
                        ],
                        language: context, appearance: appearance)
                    AuthUIFlow.signIn(app, email: MockScenarioValues.twoFactorEmail)
                    XCTAssertTrue(app.textFields["two-factor.code"].waitForExistence(timeout: 8))
                    let keyboardHidden = XCTNSPredicateExpectation(
                        predicate: NSPredicate { _, _ in !app.keyboards.firstMatch.exists }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [keyboardHidden], timeout: 5), .completed)
                    for recovery in [false, true] {
                        if recovery {
                            AuthUIFlow.reveal(app.buttons["two-factor.toggle"], in: app)
                            app.buttons["two-factor.toggle"].tap()
                        }
                        auditControls(
                            app,
                            identifiers: [
                                "auth.back", recovery ? "two-factor.recovery_code" : "two-factor.code",
                                "two-factor.submit", "two-factor.toggle",
                            ],
                            language: context, appearance: appearance)
                    }
                }
            }
        }
    }

    @MainActor private func auditControls(
        _ app: XCUIApplication, identifiers: [String], language: String, appearance: XCUIDevice.Appearance
    ) {
        for identifier in identifiers {
            let control = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 3), identifier)
            AuthUIFlow.reveal(control, in: app)
            audit(app, language: language, appearance: appearance, stage: identifier)
        }
    }

    @MainActor private func audit(
        _ app: XCUIApplication, language: String, appearance: XCUIDevice.Appearance, stage: String
    ) {
        do {
            try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType)) { issue in
                let boardContrast = Self.isBoardContrast(
                    identifier: issue.element?.identifier, auditType: issue.auditType)
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
        } catch {
            XCTFail("Auth accessibility audit failed [\(language), \(appearance), \(stage)]: \(error)")
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
            "sign-in.forgot", "sign-in.signup", "two-factor.code", "two-factor.recovery_code",
            "two-factor.submit", "two-factor.toggle", "auth.back", "auth.heading", "auth.banner", "welcome.plan",
            "sign-in.guest.new",
        ] {
            XCTAssertFalse(Self.isBoardContrast(identifier: identifier, auditType: .contrast))
        }
    }
}
