import DesignSystem
import UIKit
import XCTest

nonisolated final class AuthAuditTests: XCTestCase {
    private enum Profile { case light, dark, xxLarge }

    @MainActor private func variants(for profile: Profile) -> [(String, XCUIDevice.Appearance, Bool)] {
        switch profile {
        case .light: [("en", .light, false), ("nl", .light, false)]
        case .dark: [("en", .dark, false), ("nl", .dark, false)]
        case .xxLarge: [("en", .light, true)]
        }
    }

    @MainActor func testSignInInLeanAuditMatrix() async throws {
        try await auditSignInOrTwoFactor(mode: 0, profile: .light)
    }
    @MainActor func testSignInInLeanAuditMatrixDark() async throws {
        try await auditSignInOrTwoFactor(mode: 0, profile: .dark)
    }
    @MainActor func testSignInInLeanAuditMatrixXXLarge() async throws {
        try await auditSignInOrTwoFactor(mode: 0, profile: .xxLarge)
    }
    @MainActor func testTwoFactorCodeInLeanAuditMatrix() async throws {
        try await auditSignInOrTwoFactor(mode: 1, profile: .light)
    }
    @MainActor func testTwoFactorCodeInLeanAuditMatrixDark() async throws {
        try await auditSignInOrTwoFactor(mode: 1, profile: .dark)
    }
    @MainActor func testTwoFactorCodeInLeanAuditMatrixXXLarge() async throws {
        try await auditSignInOrTwoFactor(mode: 1, profile: .xxLarge)
    }
    @MainActor func testTwoFactorRecoveryInLeanAuditMatrix() async throws {
        try await auditSignInOrTwoFactor(mode: 2, profile: .light)
    }
    @MainActor func testTwoFactorRecoveryInLeanAuditMatrixDark() async throws {
        try await auditSignInOrTwoFactor(mode: 2, profile: .dark)
    }
    @MainActor func testTwoFactorRecoveryInLeanAuditMatrixXXLarge() async throws {
        try await auditSignInOrTwoFactor(mode: 2, profile: .xxLarge)
    }
    @MainActor func testForgotFormInLeanAuditMatrix() async throws {
        try await auditForgot(state: "form", profile: .light)
    }
    @MainActor func testForgotFormInLeanAuditMatrixDark() async throws {
        try await auditForgot(state: "form", profile: .dark)
    }
    @MainActor func testForgotFormInLeanAuditMatrixXXLarge() async throws {
        try await auditForgot(state: "form", profile: .xxLarge)
    }
    @MainActor func testForgotSentInLeanAuditMatrix() async throws {
        try await auditForgot(state: "sent", profile: .light)
    }
    @MainActor func testForgotSentInLeanAuditMatrixDark() async throws {
        try await auditForgot(state: "sent", profile: .dark)
    }
    @MainActor func testForgotSentInLeanAuditMatrixXXLarge() async throws {
        try await auditForgot(state: "sent", profile: .xxLarge)
    }
    @MainActor func testForgotFieldInLeanAuditMatrix() async throws {
        try await auditForgot(state: "field", profile: .light)
    }
    @MainActor func testForgotFieldInLeanAuditMatrixDark() async throws {
        try await auditForgot(state: "field", profile: .dark)
    }
    @MainActor func testForgotFieldInLeanAuditMatrixXXLarge() async throws {
        try await auditForgot(state: "field", profile: .xxLarge)
    }
    @MainActor func testForgotServerInLeanAuditMatrix() async throws {
        try await auditForgot(state: "server", profile: .light)
    }
    @MainActor func testForgotServerInLeanAuditMatrixDark() async throws {
        try await auditForgot(state: "server", profile: .dark)
    }
    @MainActor func testForgotServerInLeanAuditMatrixXXLarge() async throws {
        try await auditForgot(state: "server", profile: .xxLarge)
    }
    @MainActor func testForgotThrottleInLeanAuditMatrix() async throws {
        try await auditForgot(state: "throttle", profile: .light)
    }
    @MainActor func testForgotThrottleInLeanAuditMatrixDark() async throws {
        try await auditForgot(state: "throttle", profile: .dark)
    }
    @MainActor func testForgotThrottleInLeanAuditMatrixXXLarge() async throws {
        try await auditForgot(state: "throttle", profile: .xxLarge)
    }
    @MainActor func testForgotOfflineInLeanAuditMatrix() async throws {
        try await auditForgot(state: "offline", profile: .light)
    }
    @MainActor func testForgotOfflineInLeanAuditMatrixDark() async throws {
        try await auditForgot(state: "offline", profile: .dark)
    }
    @MainActor func testForgotOfflineInLeanAuditMatrixXXLarge() async throws {
        try await auditForgot(state: "offline", profile: .xxLarge)
    }

    @MainActor func testResetFormInLeanAuditMatrix() async throws {
        try await auditReset(state: "form", profile: .light)
    }
    @MainActor func testResetFormInLeanAuditMatrixDark() async throws {
        try await auditReset(state: "form", profile: .dark)
    }
    @MainActor func testResetFormInLeanAuditMatrixXXLarge() async throws {
        try await auditReset(state: "form", profile: .xxLarge)
    }
    @MainActor func testResetPasswordInLeanAuditMatrix() async throws {
        try await auditReset(state: "password", profile: .light)
    }
    @MainActor func testResetPasswordInLeanAuditMatrixDark() async throws {
        try await auditReset(state: "password", profile: .dark)
    }
    @MainActor func testResetPasswordInLeanAuditMatrixXXLarge() async throws {
        try await auditReset(state: "password", profile: .xxLarge)
    }
    @MainActor func testResetConfirmationInLeanAuditMatrix() async throws {
        try await auditReset(state: "confirmation", profile: .light)
    }
    @MainActor func testResetConfirmationInLeanAuditMatrixDark() async throws {
        try await auditReset(state: "confirmation", profile: .dark)
    }
    @MainActor func testResetConfirmationInLeanAuditMatrixXXLarge() async throws {
        try await auditReset(state: "confirmation", profile: .xxLarge)
    }
    @MainActor func testResetExpiredInLeanAuditMatrix() async throws {
        try await auditReset(state: "expired", profile: .light)
    }
    @MainActor func testResetExpiredInLeanAuditMatrixDark() async throws {
        try await auditReset(state: "expired", profile: .dark)
    }
    @MainActor func testResetExpiredInLeanAuditMatrixXXLarge() async throws {
        try await auditReset(state: "expired", profile: .xxLarge)
    }
    @MainActor func testResetDoneInLeanAuditMatrix() async throws {
        try await auditReset(state: "done", profile: .light)
    }
    @MainActor func testResetDoneInLeanAuditMatrixDark() async throws {
        try await auditReset(state: "done", profile: .dark)
    }
    @MainActor func testResetDoneInLeanAuditMatrixXXLarge() async throws {
        try await auditReset(state: "done", profile: .xxLarge)
    }
    @MainActor func testResetServerInLeanAuditMatrix() async throws {
        try await auditReset(state: "server", profile: .light)
    }
    @MainActor func testResetServerInLeanAuditMatrixDark() async throws {
        try await auditReset(state: "server", profile: .dark)
    }
    @MainActor func testResetServerInLeanAuditMatrixXXLarge() async throws {
        try await auditReset(state: "server", profile: .xxLarge)
    }
    @MainActor func testResetThrottleInLeanAuditMatrix() async throws {
        try await auditReset(state: "throttle", profile: .light)
    }
    @MainActor func testResetThrottleInLeanAuditMatrixDark() async throws {
        try await auditReset(state: "throttle", profile: .dark)
    }
    @MainActor func testResetThrottleInLeanAuditMatrixXXLarge() async throws {
        try await auditReset(state: "throttle", profile: .xxLarge)
    }
    @MainActor func testResetOfflineInLeanAuditMatrix() async throws {
        try await auditReset(state: "offline", profile: .light)
    }
    @MainActor func testResetOfflineInLeanAuditMatrixDark() async throws {
        try await auditReset(state: "offline", profile: .dark)
    }
    @MainActor func testResetOfflineInLeanAuditMatrixXXLarge() async throws {
        try await auditReset(state: "offline", profile: .xxLarge)
    }

    @MainActor private func auditReset(state: String, profile: Profile) async throws {
        try await FontRegistry.register()
        let previous = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previous }
        for (language, appearance, xxLarge) in variants(for: profile) {
            try DeviceAppearance.set(appearance)
            let app = XCUIApplication()
            app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            if state == "expired" {
                app.launchEnvironment["CF_AUTH_TEST_LINK"] = "https://app.chronoflow.net/reset-password"
            }
            if ["server", "throttle", "offline"].contains(state) {
                app.launchEnvironment["CF_AUTH_TEST_RESET_FAILURE"] = state
            }
            app.launch()
            defer { app.terminate() }
            if state == "expired" {
                XCTAssertTrue(app.textFields["forgot.email"].waitForExistence(timeout: 12))
            } else {
                openResetFromMockMail(app)
                if state != "form" {
                    fillReset(
                        app, password: state == "password" ? "short" : "NewPassword123!",
                        confirmation: state == "confirmation"
                            ? "different" : state == "password" ? "short" : "NewPassword123!")
                    if state == "done" {
                        XCTAssertTrue(app.buttons["reset.continue"].waitForExistence(timeout: 6))
                    } else {
                        let finished = XCTNSPredicateExpectation(
                            predicate: NSPredicate { _, _ in app.secureTextFields["reset.password"].isEnabled },
                            object: nil)
                        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 6), .completed)
                    }
                }
            }
            let identifiers =
                state == "expired"
                ? ["auth.back", "forgot.email", "forgot.submit", "forgot.back"]
                : state == "done"
                    ? ["reset.continue"]
                    : ["reset.password", "reset.confirmation", "reset.submit"]
                        + (["server", "throttle"].contains(state) ? ["auth.banner"] : [])
            auditControls(
                app, identifiers: identifiers, language: "\(language), reset-\(state)", appearance: appearance,
                xxLarge: xxLarge)
        }
    }

    @MainActor func testSignUpFormInLeanAuditMatrix() async throws {
        try await auditSignUp(state: "form", profile: .light)
    }
    @MainActor func testSignUpFormInLeanAuditMatrixDark() async throws {
        try await auditSignUp(state: "form", profile: .dark)
    }
    @MainActor func testSignUpFormInLeanAuditMatrixXXLarge() async throws {
        try await auditSignUp(state: "form", profile: .xxLarge)
    }
    @MainActor func testSignUpEmptyInLeanAuditMatrix() async throws {
        try await auditSignUp(state: "empty", profile: .light)
    }
    @MainActor func testSignUpEmptyInLeanAuditMatrixDark() async throws {
        try await auditSignUp(state: "empty", profile: .dark)
    }
    @MainActor func testSignUpEmptyInLeanAuditMatrixXXLarge() async throws {
        try await auditSignUp(state: "empty", profile: .xxLarge)
    }
    @MainActor func testSignUpEmailInLeanAuditMatrix() async throws {
        try await auditSignUp(state: "email", profile: .light)
    }
    @MainActor func testSignUpEmailInLeanAuditMatrixDark() async throws {
        try await auditSignUp(state: "email", profile: .dark)
    }
    @MainActor func testSignUpEmailInLeanAuditMatrixXXLarge() async throws {
        try await auditSignUp(state: "email", profile: .xxLarge)
    }
    @MainActor func testSignUpTakenInLeanAuditMatrix() async throws {
        try await auditSignUp(state: "taken", profile: .light)
    }
    @MainActor func testSignUpTakenInLeanAuditMatrixDark() async throws {
        try await auditSignUp(state: "taken", profile: .dark)
    }
    @MainActor func testSignUpTakenInLeanAuditMatrixXXLarge() async throws {
        try await auditSignUp(state: "taken", profile: .xxLarge)
    }
    @MainActor func testSignUpPasswordInLeanAuditMatrix() async throws {
        try await auditSignUp(state: "password", profile: .light)
    }
    @MainActor func testSignUpPasswordInLeanAuditMatrixDark() async throws {
        try await auditSignUp(state: "password", profile: .dark)
    }
    @MainActor func testSignUpPasswordInLeanAuditMatrixXXLarge() async throws {
        try await auditSignUp(state: "password", profile: .xxLarge)
    }
    @MainActor func testSignUpConfirmationInLeanAuditMatrix() async throws {
        try await auditSignUp(state: "confirmation", profile: .light)
    }
    @MainActor func testSignUpConfirmationInLeanAuditMatrixDark() async throws {
        try await auditSignUp(state: "confirmation", profile: .dark)
    }
    @MainActor func testSignUpConfirmationInLeanAuditMatrixXXLarge() async throws {
        try await auditSignUp(state: "confirmation", profile: .xxLarge)
    }
    @MainActor func testSignUpVisibleInLeanAuditMatrix() async throws {
        try await auditSignUp(state: "visible", profile: .light)
    }
    @MainActor func testSignUpVisibleInLeanAuditMatrixDark() async throws {
        try await auditSignUp(state: "visible", profile: .dark)
    }
    @MainActor func testSignUpVisibleInLeanAuditMatrixXXLarge() async throws {
        try await auditSignUp(state: "visible", profile: .xxLarge)
    }
    @MainActor func testSignUpServerInLeanAuditMatrix() async throws {
        try await auditSignUp(state: "server", profile: .light)
    }
    @MainActor func testSignUpServerInLeanAuditMatrixDark() async throws {
        try await auditSignUp(state: "server", profile: .dark)
    }
    @MainActor func testSignUpServerInLeanAuditMatrixXXLarge() async throws {
        try await auditSignUp(state: "server", profile: .xxLarge)
    }
    @MainActor func testSignUpThrottleInLeanAuditMatrix() async throws {
        try await auditSignUp(state: "throttle", profile: .light)
    }
    @MainActor func testSignUpThrottleInLeanAuditMatrixDark() async throws {
        try await auditSignUp(state: "throttle", profile: .dark)
    }
    @MainActor func testSignUpThrottleInLeanAuditMatrixXXLarge() async throws {
        try await auditSignUp(state: "throttle", profile: .xxLarge)
    }
    @MainActor func testSignUpOfflineInLeanAuditMatrix() async throws {
        try await auditSignUp(state: "offline", profile: .light)
    }
    @MainActor func testSignUpOfflineInLeanAuditMatrixDark() async throws {
        try await auditSignUp(state: "offline", profile: .dark)
    }
    @MainActor func testSignUpOfflineInLeanAuditMatrixXXLarge() async throws {
        try await auditSignUp(state: "offline", profile: .xxLarge)
    }

    @MainActor private func auditSignUp(state: String, profile: Profile) async throws {
        try await FontRegistry.register()
        let previous = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previous }
        for (language, appearance, xxLarge) in variants(for: profile) {
            try DeviceAppearance.set(appearance)
            let app = XCUIApplication()
            app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            if ["server", "throttle", "offline"].contains(state) {
                app.launchEnvironment["CF_AUTH_TEST_SIGNUP_FAILURE"] = state
            }
            app.launch()
            defer { app.terminate() }
            openSignUp(app)
            if state == "empty" {
                AuthUIFlow.reveal(app.buttons["sign-up.submit"], in: app)
                app.buttons["sign-up.submit"].tap()
            } else if state == "visible" {
                AuthUIFlow.reveal(app.switches["sign-up.visibility"], in: app)
                app.switches["sign-up.visibility"].tap()
            } else if state != "form" {
                fillSignUp(
                    app,
                    email: state == "taken"
                        ? MockScenarioValues.demoEmail : state == "email" ? "invalid" : "new@example.com",
                    password: state == "password" ? "short" : "NewPassword123!",
                    confirmation: state == "confirmation" ? "different" : nil)
            }
            if !["form", "visible"].contains(state) {
                let finished = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in app.textFields["sign-up.name"].isEnabled }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 6), .completed)
            }
            auditControls(
                app,
                identifiers: [
                    "auth.back", "sign-up.name", "sign-up.email", "sign-up.password", "sign-up.confirmation",
                    "sign-up.visibility", "sign-up.submit", "sign-up.consent", "sign-up.back",
                ] + (["taken", "server", "throttle"].contains(state) ? ["auth.banner"] : []),
                language: "\(language), sign-up-\(state)", appearance: appearance, xxLarge: xxLarge)
        }
    }

    @MainActor func testVerifyWaitingInLeanAuditMatrix() async throws {
        try await auditVerify(state: "waiting", profile: .light)
    }
    @MainActor func testVerifyWaitingInLeanAuditMatrixDark() async throws {
        try await auditVerify(state: "waiting", profile: .dark)
    }
    @MainActor func testVerifyWaitingInLeanAuditMatrixXXLarge() async throws {
        try await auditVerify(state: "waiting", profile: .xxLarge)
    }
    @MainActor func testVerifyCountdownInLeanAuditMatrix() async throws {
        try await auditVerify(state: "countdown", profile: .light)
    }
    @MainActor func testVerifyCountdownInLeanAuditMatrixDark() async throws {
        try await auditVerify(state: "countdown", profile: .dark)
    }
    @MainActor func testVerifyCountdownInLeanAuditMatrixXXLarge() async throws {
        try await auditVerify(state: "countdown", profile: .xxLarge)
    }
    @MainActor func testVerifyFailedInLeanAuditMatrix() async throws {
        try await auditVerify(state: "failed", profile: .light)
    }
    @MainActor func testVerifyFailedInLeanAuditMatrixDark() async throws {
        try await auditVerify(state: "failed", profile: .dark)
    }
    @MainActor func testVerifyFailedInLeanAuditMatrixXXLarge() async throws {
        try await auditVerify(state: "failed", profile: .xxLarge)
    }
    @MainActor func testVerifyServerInLeanAuditMatrix() async throws {
        try await auditVerify(state: "server", profile: .light)
    }
    @MainActor func testVerifyServerInLeanAuditMatrixDark() async throws {
        try await auditVerify(state: "server", profile: .dark)
    }
    @MainActor func testVerifyServerInLeanAuditMatrixXXLarge() async throws {
        try await auditVerify(state: "server", profile: .xxLarge)
    }
    @MainActor func testVerifyThrottleInLeanAuditMatrix() async throws {
        try await auditVerify(state: "throttle", profile: .light)
    }
    @MainActor func testVerifyThrottleInLeanAuditMatrixDark() async throws {
        try await auditVerify(state: "throttle", profile: .dark)
    }
    @MainActor func testVerifyThrottleInLeanAuditMatrixXXLarge() async throws {
        try await auditVerify(state: "throttle", profile: .xxLarge)
    }
    @MainActor func testVerifyOfflineInLeanAuditMatrix() async throws {
        try await auditVerify(state: "offline", profile: .light)
    }
    @MainActor func testVerifyOfflineInLeanAuditMatrixDark() async throws {
        try await auditVerify(state: "offline", profile: .dark)
    }
    @MainActor func testVerifyOfflineInLeanAuditMatrixXXLarge() async throws {
        try await auditVerify(state: "offline", profile: .xxLarge)
    }
    @MainActor func testVerifySignOutErrorInLeanAuditMatrix() async throws {
        try await auditVerify(state: "signOutError", profile: .light)
    }
    @MainActor func testVerifySignOutErrorInLeanAuditMatrixDark() async throws {
        try await auditVerify(state: "signOutError", profile: .dark)
    }
    @MainActor func testVerifySignOutErrorInLeanAuditMatrixXXLarge() async throws {
        try await auditVerify(state: "signOutError", profile: .xxLarge)
    }

    @MainActor func testVerifyFailedServerInLeanAuditMatrix() async throws {
        try await auditVerify(state: "failedServer", profile: .light)
    }
    @MainActor func testVerifyFailedServerInLeanAuditMatrixDark() async throws {
        try await auditVerify(state: "failedServer", profile: .dark)
    }
    @MainActor func testVerifyFailedServerInLeanAuditMatrixXXLarge() async throws {
        try await auditVerify(state: "failedServer", profile: .xxLarge)
    }
    @MainActor func testVerifyFailedThrottleInLeanAuditMatrix() async throws {
        try await auditVerify(state: "failedThrottle", profile: .light)
    }
    @MainActor func testVerifyFailedThrottleInLeanAuditMatrixDark() async throws {
        try await auditVerify(state: "failedThrottle", profile: .dark)
    }
    @MainActor func testVerifyFailedThrottleInLeanAuditMatrixXXLarge() async throws {
        try await auditVerify(state: "failedThrottle", profile: .xxLarge)
    }
    @MainActor func testVerifyFailedOfflineInLeanAuditMatrix() async throws {
        try await auditVerify(state: "failedOffline", profile: .light)
    }
    @MainActor func testVerifyFailedOfflineInLeanAuditMatrixDark() async throws {
        try await auditVerify(state: "failedOffline", profile: .dark)
    }
    @MainActor func testVerifyFailedOfflineInLeanAuditMatrixXXLarge() async throws {
        try await auditVerify(state: "failedOffline", profile: .xxLarge)
    }

    @MainActor private func auditVerify(state: String, profile: Profile) async throws {
        try await FontRegistry.register()
        let previous = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previous }
        for (language, appearance, xxLarge) in variants(for: profile) {
            try DeviceAppearance.set(appearance)
            let app = XCUIApplication()
            app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            app.launchEnvironment["CF_AUTH_TEST_VERIFY_STATE"] = state
            if state.hasPrefix("failed") {
                app.launchEnvironment["CF_AUTH_TEST_UNVERIFIED"] = "1"
                app.launchEnvironment["CF_AUTH_TEST_LINK"] = tamperedVerificationURL()
            }
            app.launch()
            defer { app.terminate() }
            if state.hasPrefix("failed") {
                AuthUIFlow.openSignIn(app)
                AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
            } else {
                openSignUp(app)
                fillSignUp(app, email: "verify@example.com")
            }
            let first = app.buttons[state.hasPrefix("failed") ? "verify.retry" : "verify.open-email"]
            XCTAssertTrue(first.waitForExistence(timeout: 8))
            AuthUIFlow.waitUntilEnabled(first)
            if ["countdown", "throttle", "server", "offline", "failedServer", "failedThrottle", "failedOffline"]
                .contains(state)
            {
                let resend = app.buttons["verify.resend"]
                let enabled = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in resend.isEnabled }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 6), .completed)
                AuthUIFlow.reveal(resend, in: app)
                resend.tap()
                if state != "offline" && state != "failedOffline" {
                    XCTAssertTrue(AuthUIFlow.control("auth.banner", in: app).waitForExistence(timeout: 6))
                }
                if state == "countdown" {
                    XCUIDevice.shared.press(.home)
                    app.activate()
                }
            } else if state == "signOutError" {
                let back = app.buttons["verify.different-email"]
                AuthUIFlow.reveal(back, in: app)
                back.tap()
                XCTAssertTrue(AuthUIFlow.control("verify.sign-out-error", in: app).waitForExistence(timeout: 6))
            }
            let identifiers =
                (state.hasPrefix("failed")
                    ? ["auth.back", "verify.retry", "verify.resend"]
                    : ["auth.back", "verify.open-email", "verify.resend", "verify.different-email"])
                + (["countdown", "throttle"].contains(state) ? ["verify.countdown"] : [])
                + (["server", "throttle", "failedServer", "failedThrottle"].contains(state) ? ["auth.banner"] : [])
                + (state == "signOutError" ? ["verify.sign-out-error"] : [])
            auditControls(
                app, identifiers: identifiers, language: "\(language), verify-\(state)", appearance: appearance,
                xxLarge: xxLarge)
        }
    }

    @MainActor private func auditSignInOrTwoFactor(mode: Int, profile: Profile) async throws {
        try await FontRegistry.register()
        let device = XCUIDevice.shared
        let previous = device.appearance
        defer { device.appearance = previous }
        for (language, appearance, xxLarge) in variants(for: profile) {
            try DeviceAppearance.set(appearance)
            let app = XCUIApplication()
            app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            app.launch()
            defer { app.terminate() }
            AuthUIFlow.openSignIn(app)
            if mode > 0 {
                AuthUIFlow.signIn(app, email: MockScenarioValues.twoFactorEmail)
                XCTAssertTrue(app.textFields["two-factor.code"].waitForExistence(timeout: 8))
                let keyboardHidden = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in !app.keyboards.firstMatch.exists }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [keyboardHidden], timeout: 5), .completed)
                if mode == 2 {
                    AuthUIFlow.reveal(app.buttons["two-factor.toggle"], in: app)
                    app.buttons["two-factor.toggle"].tap()
                }
            }
            auditControls(
                app,
                identifiers: mode == 0
                    ? [
                        "auth.back", "sign-in.passkey", "sign-in.email", "sign-in.password",
                        "sign-in.submit", "sign-in.forgot", "sign-in.signup", "sign-in.guest",
                    ]
                    : [
                        "auth.back", mode == 2 ? "two-factor.recovery_code" : "two-factor.code",
                        "two-factor.submit", "two-factor.toggle",
                    ],
                language: "\(language), \(xxLarge ? "xxLarge" : "default")", appearance: appearance, xxLarge: xxLarge)
        }
    }

    @MainActor private func auditForgot(state: String, profile: Profile) async throws {
        try await FontRegistry.register()
        let device = XCUIDevice.shared
        let previous = device.appearance
        defer { device.appearance = previous }
        for (language, appearance, xxLarge) in variants(for: profile) {
            try DeviceAppearance.set(appearance)
            let app = launchForgotApp(
                language: language, xxLarge: xxLarge, failure: state, offline: state == "offline")
            defer { app.terminate() }
            openForgot(app)
            if state != "form" {
                let field = app.textFields["forgot.email"]
                field.tap()
                field.typeText(state == "field" ? "invalid\n" : "unknown@example.com\n")
                if state == "sent" {
                    XCTAssertTrue(AuthUIFlow.control("forgot.notice", in: app).waitForExistence(timeout: 6))
                } else if state == "server" || state == "throttle" {
                    XCTAssertTrue(
                        AuthUIFlow.control("auth.banner", in: app).waitForExistence(timeout: 6),
                        "Missing Forgot \(state) banner: \(language), \(appearance), xxLarge=\(xxLarge)")
                } else {
                    let received = XCTNSPredicateExpectation(
                        predicate: NSPredicate { _, _ in
                            field.isEnabled && field.value(forKey: "hasKeyboardFocus") as? Bool == true
                        }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 6), .completed)
                }
            }
            let identifiers =
                state == "sent"
                ? ["auth.back", "forgot.notice", "forgot.open-email", "forgot.back"]
                : ["auth.back", "forgot.email", "forgot.submit"]
                    + (["server", "throttle"].contains(state) ? ["auth.banner"] : [])
            auditControls(
                app, identifiers: identifiers, language: "\(language), \(state), \(xxLarge ? "xxLarge" : "default")",
                appearance: appearance, xxLarge: xxLarge, forgotBannerState: state)
        }
    }

    @MainActor private func auditControls(
        _ app: XCUIApplication, identifiers: [String], language: String, appearance: XCUIDevice.Appearance,
        xxLarge: Bool, forgotBannerState: String? = nil
    ) {
        AuthUIFlow.dismissKeyboard(in: app)
        let identifiers = ["auth.brand", "auth.heading", "auth.subtitle"] + identifiers
        var auditedPositions: [[CGRect]] = []
        for identifier in identifiers {
            let matches = AuthUIFlow.scroll(in: app).descendants(matching: .any).matching(identifier: identifier)
            guard matches.firstMatch.waitForExistence(timeout: 3), matches.count == 1 else {
                XCTFail("Expected one accessibility element for \(identifier); found \(matches.count)")
                return
            }
            let control = matches.element
            AuthUIFlow.reveal(control, in: app)
            do {
                _ = try UIWait.stableFrames(
                    [control, AuthUIFlow.control("auth.subtitle", in: app), AuthUIFlow.scroll(in: app)], timeout: 3)
            } catch {
                XCTFail("Audit frames did not settle for \(identifier): \(error)")
                return
            }
            let position = [
                AuthUIFlow.control("auth.subtitle", in: app).frame,
                AuthUIFlow.scroll(in: app).frame,
                app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame : .zero,
            ]
            guard !auditedPositions.contains(position) else { continue }
            auditedPositions.append(position)
            audit(
                app, language: language, appearance: appearance, stage: identifier, xxLarge: xxLarge,
                forgotBannerState: forgotBannerState, identifiers: identifiers)
        }
    }

    @MainActor private func audit(
        _ app: XCUIApplication, language: String, appearance: XCUIDevice.Appearance, stage: String, xxLarge: Bool,
        forgotBannerState: String?, identifiers: [String]
    ) {
        let viewport = AuthUIFlow.viewport(in: app, scrollFrame: AuthUIFlow.scroll(in: app).frame)
        let controlFrames = identifiers.map { AuthUIFlow.control($0, in: app).frame }
        let brand = AuthUIFlow.control("auth.brand", in: app)
        let brandFrame: CGRect? = brand.exists ? brand.frame : nil
        var brandMinimum: Double?
        var brandMeasurement = "not visible"
        if let brandFrame, viewport.insetBy(dx: -Self.frameTolerance, dy: -Self.frameTolerance).contains(brandFrame) {
            (brandMinimum, brandMeasurement) = textContrast(
                brand, in: app, appearance: appearance, xxLarge: xxLarge, brand: true)
        }
        var bannerMinimum: Double?
        var bannerFrame: CGRect?
        var bannerMeasurement = "not eligible"
        if ["server", "throttle"].contains(forgotBannerState ?? ""), app.scrollViews["forgot.scroll"].exists {
            let banner = AuthUIFlow.control("auth.banner", in: app)
            if banner.exists {
                bannerFrame = banner.frame
                (bannerMinimum, bannerMeasurement) = textContrast(
                    banner, in: app, appearance: appearance, xxLarge: xxLarge, banner: true)
                print("Forgot banner contrast [\(language), \(appearance), \(stage)]: \(bannerMeasurement)")
                if let bannerMinimum {
                    XCTAssertGreaterThanOrEqual(bannerMinimum, 4.5, bannerMeasurement)
                }
            }
        }
        do {
            try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType)) { issue in
                if Self.isDeferredControlContrast(
                    auditType: issue.auditType, frame: issue.element?.frame, viewport: viewport,
                    controlFrames: controlFrames)
                {
                    return true
                }
                let boardContrast = Self.isBoardContrast(
                    identifier: issue.element?.identifier, auditType: issue.auditType)
                var minimum: Double?
                var measurement = "not eligible"
                if issue.auditType == .contrast, let element = issue.element, element.identifier == "auth.subtitle" {
                    (minimum, measurement) = self.textContrast(
                        element, in: app, appearance: appearance, xxLarge: xxLarge)
                }
                let ignored =
                    boardContrast
                    || Self.isMeasuredSubtitleContrast(
                        identifier: issue.element?.identifier, auditType: issue.auditType, minimum: minimum)
                    || Self.isMeasuredBrandContrast(
                        identifier: issue.element?.identifier, frame: issue.element?.frame, brandFrame: brandFrame,
                        auditType: issue.auditType, minimum: brandMinimum)
                    || Self.isMeasuredForgotBannerContrast(
                        identifier: issue.element?.identifier, frame: issue.element?.frame, bannerFrame: bannerFrame,
                        auditType: issue.auditType,
                        state: forgotBannerState, minimum: bannerMinimum)
                let message = """
                    Auth accessibility [\(language), \(appearance), \(stage)] \
                    auditType=\(issue.auditType) identifier=\(issue.element?.identifier ?? "<nil>") \
                    label=\(issue.element?.label ?? "<nil>") compactDescription=\(issue.compactDescription) \
                    frame=\(String(describing: issue.element?.frame)) bannerFrame=\(String(describing: bannerFrame)) \
                    brandFrame=\(String(describing: brandFrame)) brandMinimum=\(String(describing: brandMinimum)) \
                    boardContrast=\(boardContrast) ignored=\(ignored) subtitleMinimum=\(minimum.map { "\($0):1" } ?? "unmeasurable")
                    \(measurement)
                    bannerMinimum=\(bannerMinimum.map { "\($0):1" } ?? "unmeasurable")
                    \(bannerMeasurement)
                    \(brandMeasurement)
                    """
                print(message)
                let attachment = XCTAttachment(string: message)
                attachment.lifetime = .keepAlways
                self.add(attachment)
                if !ignored { XCTFail(message) }
                return ignored
            }
        } catch {
            XCTFail("Auth accessibility audit failed [\(language), \(appearance), \(stage)]: \(error)")
        }
    }

    @MainActor private func textContrast(
        _ element: XCUIElement, in app: XCUIApplication, appearance: XCUIDevice.Appearance, xxLarge: Bool,
        banner: Bool = false, brand: Bool = false
    ) -> (Double?, String) {
        let identifier = banner ? "auth.banner" : brand ? "auth.brand" : "auth.subtitle"
        let scrolls = app.scrollViews.containing(.any, identifier: identifier).allElementsBoundByIndex
        let matches = scrolls.filter { scroll in
            let elements = scroll.descendants(matching: .any).matching(identifier: identifier)
            return elements.count == 1 && elements.element.frame == element.frame
                && elements.element.label == element.label
        }
        guard banner || brand || element.elementType == .staticText, matches.count == 1, let scroll = matches.first
        else {
            return (nil, "No unique \(identifier) in the current auth screen")
        }
        let appFrame = app.frame
        var frame = element.frame.offsetBy(dx: -appFrame.minX, dy: -appFrame.minY)
        if banner {
            frame = frame.insetBy(dx: AuthTokens.bannerHorizontal, dy: AuthTokens.bannerVertical)
            let glyph = AuthTokens.bannerGlyph + AuthTokens.bannerGap
            frame.origin.x += glyph
            frame.size.width -= glyph
        }
        if brand {
            let glyph = AuthTokens.moon + AuthTokens.brandGap
            frame.origin.x += glyph
            frame.size.width -= glyph
        }
        let viewport = AuthUIFlow.viewport(in: app, scrollFrame: scroll.frame)
            .offsetBy(dx: -appFrame.minX, dy: -appFrame.minY)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(identifier) contrast source"
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            let raster = try SnapshotRaster(png: screenshot.pngRepresentation)
            let scale = CGFloat(raster.width) / appFrame.width
            guard scale.isFinite, scale > 0, abs(CGFloat(raster.height) / scale - appFrame.height) < 1 else {
                return (nil, "Screenshot and app bounds disagree: \(raster.width)×\(raster.height), app=\(appFrame)")
            }
            let traits = UITraitCollection {
                $0.userInterfaceStyle = appearance == .dark ? .dark : .light
                $0.preferredContentSizeCategory = xxLarge ? .extraExtraLarge : .large
            }
            let token: ColorToken = banner ? .cardForeground : .skyTitle
            let typography = banner ? Typography.authHint : brand ? Typography.authBrand : Typography.authBody
            guard
                let rgb = UIColor(token.color).resolvedColor(with: traits).cgColor.converted(
                    to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric, options: nil)?.components
            else { return (nil, "Cannot convert \(identifier) ink to sRGB") }
            let font = typography.uiFont(compatibleWith: traits)
            guard let leading = typography.lineHeight else { return (nil, "Missing \(identifier) leading") }
            let measurement = RenderedTextContrast.measure(
                raster: raster, frame: frame, scale: scale,
                lineHeight: leading * font.pointSize / typography.size,
                text: Array(rgb.prefix(3)).map(Double.init), viewport: viewport)
            let lines = measurement.lines.enumerated().map { index, line in
                "line=\(index + 1), frame=\(line.frame), ratio=\(line.minimum)...\(line.maximum):1, ink=\(line.ink)"
            }.joined(separator: "\n")
            return (
                measurement.minimum,
                "\(identifier)=\(frame), viewport=\(viewport), scale=\(scale), tokens=\(banner ? "cardForeground/authErrorBackground" : "skyTitle/cf-sky"), minimum=\(measurement.minimum.map { "\($0):1" } ?? "unmeasurable"), measuredLines=\(measurement.lines.count)/\(measurement.expectedLines)\n\(lines)"
            )
        } catch {
            return (nil, "\(identifier) screenshot measurement failed: \(error)")
        }
    }

    @MainActor private static func isMeasuredSubtitleContrast(
        identifier: String?, auditType: XCUIAccessibilityAuditType, minimum: Double?
    ) -> Bool {
        guard auditType == .contrast, identifier == "auth.subtitle", let minimum else { return false }
        return minimum.isFinite && minimum >= 4.5
    }

    // Audit frames are Double; element frames round-trip through Float, so exact containment misses by ~1e-6.
    private static let frameTolerance: CGFloat = 0.01

    @MainActor private static func isDeferredControlContrast(
        auditType: XCUIAccessibilityAuditType, frame: CGRect?, viewport: CGRect, controlFrames: [CGRect]
    ) -> Bool {
        guard auditType == .contrast, let frame, !frame.isEmpty, !frame.isInfinite,
            !viewport.isEmpty, !viewport.isInfinite,
            !viewport.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
        else { return false }
        // Each scheduled control is revealed and audited in full before this screen finishes.
        return controlFrames.contains {
            !$0.isEmpty && !$0.isInfinite && $0.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
        }
    }

    @MainActor private static func isMeasuredBrandContrast(
        identifier: String?, frame: CGRect?, brandFrame: CGRect?, auditType: XCUIAccessibilityAuditType,
        minimum: Double?
    ) -> Bool {
        guard auditType == .contrast, identifier == nil || identifier == "",
            let frame, !frame.isEmpty, !frame.isInfinite,
            let brandFrame, !brandFrame.isEmpty, !brandFrame.isInfinite,
            let minimum, minimum.isFinite, minimum >= 4.5
        else { return false }
        return brandFrame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
    }

    @MainActor func testWordmarkExceptionRequiresItsOwnGeometryAndPassingPixels() {
        let brand = CGRect(x: 130, y: 63, width: 140, height: 24)
        let wordmark = CGRect(x: 158, y: 62.999999, width: 112.000001, height: 24.000002)
        for identifier: String? in [nil, ""] {
            XCTAssertTrue(
                Self.isMeasuredBrandContrast(
                    identifier: identifier, frame: wordmark, brandFrame: brand, auditType: .contrast, minimum: 4.5))
        }
        for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
            XCTAssertFalse(
                Self.isMeasuredBrandContrast(
                    identifier: nil, frame: wordmark, brandFrame: brand, auditType: .contrast, minimum: minimum))
        }
        for frame: CGRect? in [nil, .zero, .null, .infinite, wordmark.offsetBy(dx: 0, dy: 1)] {
            XCTAssertFalse(
                Self.isMeasuredBrandContrast(
                    identifier: nil, frame: frame, brandFrame: brand, auditType: .contrast, minimum: 15))
            XCTAssertFalse(
                Self.isMeasuredBrandContrast(
                    identifier: nil, frame: wordmark, brandFrame: frame, auditType: .contrast, minimum: 15))
        }
        for identifier in ["auth.brand", "auth.banner", "sign-up.submit", "auth.subtitle"] {
            XCTAssertFalse(
                Self.isMeasuredBrandContrast(
                    identifier: identifier, frame: wordmark, brandFrame: brand, auditType: .contrast, minimum: 15))
        }
        for type: XCUIAccessibilityAuditType in [.textClipped, .hitRegion, .trait, .all, [.contrast, .textClipped]] {
            XCTAssertFalse(
                Self.isMeasuredBrandContrast(
                    identifier: nil, frame: wordmark, brandFrame: brand, auditType: type, minimum: 15))
        }
    }

    @MainActor func testOnlyClippedScheduledControlContrastCanWaitForItsReveal() {
        let viewport = CGRect(x: 0, y: 47, width: 390, height: 500)
        let button = CGRect(x: 36, y: 530, width: 318, height: 44)
        XCTAssertTrue(
            Self.isDeferredControlContrast(
                auditType: .contrast, frame: button, viewport: viewport, controlFrames: [button]))
        for frame: CGRect? in [nil, .zero, .null, .infinite, button.offsetBy(dx: 0, dy: 50)] {
            XCTAssertFalse(
                Self.isDeferredControlContrast(
                    auditType: .contrast, frame: frame, viewport: viewport, controlFrames: [button]))
        }
        XCTAssertFalse(
            Self.isDeferredControlContrast(
                auditType: .contrast, frame: button, viewport: viewport, controlFrames: []))
        XCTAssertFalse(
            Self.isDeferredControlContrast(
                auditType: .contrast, frame: button, viewport: viewport.insetBy(dx: 0, dy: -100),
                controlFrames: [button]))
        XCTAssertFalse(
            Self.isDeferredControlContrast(
                auditType: .textClipped, frame: button, viewport: viewport, controlFrames: [button]))
    }

    @MainActor private static func isMeasuredForgotBannerContrast(
        identifier: String?, frame: CGRect?, bannerFrame: CGRect?,
        auditType: XCUIAccessibilityAuditType,
        state: String?, minimum: Double?
    ) -> Bool {
        guard auditType == .contrast, ["server", "throttle"].contains(state ?? ""),
            identifier == nil || identifier == "" || identifier == "auth.banner",
            let frame, !frame.isEmpty, !frame.isInfinite,
            let bannerFrame, !bannerFrame.isEmpty, !bannerFrame.isInfinite,
            let minimum
        else { return false }
        return minimum.isFinite && minimum >= 4.5
            && bannerFrame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
    }

    @MainActor func testBannerExceptionRequiresMatchingGeometryAndPassingPixels() {
        let banner = CGRect(x: 30, y: 300, width: 330, height: 64)
        let title = CGRect(x: 78, y: 312, width: 262, height: 20)
        for state in ["server", "throttle"] {
            for identifier: String? in [nil, "", "auth.banner"] {
                for frame in [banner, title] {
                    XCTAssertTrue(
                        Self.isMeasuredForgotBannerContrast(
                            identifier: identifier, frame: frame, bannerFrame: banner,
                            auditType: .contrast, state: state, minimum: 4.5))
                }
            }
        }
        for frame in [title.offsetBy(dx: 0, dy: 100), CGRect(x: 158, y: 63, width: 112, height: 24)] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: nil, frame: frame, bannerFrame: banner,
                    auditType: .contrast, state: "server", minimum: 14.884))
        }
        for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: nil, frame: title, bannerFrame: banner,
                    auditType: .contrast, state: "server", minimum: minimum))
        }
        for state: String? in [nil, "form", "sent", "field", "offline", "sign-in"] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: nil, frame: title, bannerFrame: banner,
                    auditType: .contrast, state: state, minimum: 10))
        }
        for identifier in ["auth.banner.new", "auth.back", "forgot.email", "forgot.submit", "auth.subtitle"] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: identifier, frame: title, bannerFrame: banner,
                    auditType: .contrast, state: "server", minimum: 10))
        }
        for invalid: CGRect? in [
            nil, .zero, .null, .infinite, CGRect(x: 30, y: 270, width: 330, height: 40),
            CGRect(x: 40, y: 100, width: 44, height: 44),
        ] {
            for identifier: String? in [nil, "", "auth.banner"] {
                XCTAssertFalse(
                    Self.isMeasuredForgotBannerContrast(
                        identifier: identifier, frame: invalid, bannerFrame: banner,
                        auditType: .contrast, state: "server", minimum: 10))
                XCTAssertFalse(
                    Self.isMeasuredForgotBannerContrast(
                        identifier: identifier, frame: title, bannerFrame: invalid,
                        auditType: .contrast, state: "server", minimum: 10))
            }
        }
        for type: XCUIAccessibilityAuditType in [
            .textClipped, .dynamicType, .hitRegion, .trait, .all,
            [.contrast, .textClipped],
        ] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: nil, frame: title, bannerFrame: banner,
                    auditType: type, state: "server", minimum: 10))
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
            "two-factor.submit", "two-factor.toggle", "forgot.email", "forgot.submit", "forgot.notice",
            "forgot.open-email", "forgot.back", "auth.back", "auth.heading", "auth.banner", "welcome.plan",
            "sign-in.guest.new", "auth.subtitle",
        ] {
            XCTAssertFalse(Self.isBoardContrast(identifier: identifier, auditType: .contrast))
        }
    }

    @MainActor func testSubtitleExceptionRequiresAnExactContrastIssueAndAMeasuredPassingMinimum() {
        for minimum in [4.5, 10.8] {
            XCTAssertTrue(
                Self.isMeasuredSubtitleContrast(identifier: "auth.subtitle", auditType: .contrast, minimum: minimum))
        }
        for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
            XCTAssertFalse(
                Self.isMeasuredSubtitleContrast(identifier: "auth.subtitle", auditType: .contrast, minimum: minimum))
        }
        for identifier in [nil, "", "auth.subtitle.new", "auth.heading", "two-factor.toggle", "sign-in.submit"] {
            XCTAssertFalse(Self.isMeasuredSubtitleContrast(identifier: identifier, auditType: .contrast, minimum: 10.8))
        }
        for type: XCUIAccessibilityAuditType in [.textClipped, .hitRegion, .trait, .all, [.contrast, .textClipped]] {
            XCTAssertFalse(Self.isMeasuredSubtitleContrast(identifier: "auth.subtitle", auditType: type, minimum: 10.8))
        }
    }
}
