import XCTest

nonisolated final class WelcomeAuditPolicyTests: XCTestCase {
    @MainActor
    func testAuditVisibilityRejectsPartiallyVisibleAndEmptyActions() {
        let window = CGRect(x: 0, y: 0, width: 466, height: 678)
        let button = CGRect(x: 24, y: 600, width: 418, height: 52)
        XCTAssertTrue(WelcomeAuditPolicy.isFullyVisible(button, in: window))
        for frame in [
            button.offsetBy(dx: 0, dy: 27), button.offsetBy(dx: 0, dy: -601),
            button.offsetBy(dx: -25, dy: 0), button.offsetBy(dx: 25, dy: 0),
            CGRect.zero, .null, .infinite,
        ] {
            XCTAssertFalse(WelcomeAuditPolicy.isFullyVisible(frame, in: window))
        }
    }

    @MainActor
    func testAuditTypesRespectTheUserDynamicTypeCap() {
        XCTAssertEqual(
            WelcomeAuditPolicy.welcomeAuditTypes, XCUIAccessibilityAuditType.all.subtracting(.dynamicType),
            "User decision 2026-11-06: cap Dynamic Type at xxLarge; audit every other accessibility type")
        XCTAssertFalse(
            WelcomeAuditPolicy.welcomeAuditTypes.contains(.dynamicType),
            "User decision 2026-11-06: xxLarge is the maximum supported Dynamic Type size")
    }

    @MainActor
    func testAuditIgnoresOnlyContrastOnElementsOutsideTheWindowOrBoardPairs() {
        let window = CGRect(x: 0, y: 0, width: 375, height: 667)
        let visible = CGRect(x: 24, y: 590, width: 327, height: 52)
        let partial = visible.offsetBy(dx: 0, dy: 26)
        XCTAssertTrue(
            WelcomeAuditPolicy.shouldIgnoreAuditIssue(
                identifier: "welcome.plan", auditType: .contrast, elementFrame: partial, window: window))
        for identifier in ["welcome.wordmark", "welcome.newElement"] {
            XCTAssertTrue(
                WelcomeAuditPolicy.shouldIgnoreAuditIssue(
                    identifier: identifier, auditType: .contrast, elementFrame: partial, window: window))
            XCTAssertFalse(
                WelcomeAuditPolicy.shouldIgnoreAuditIssue(
                    identifier: identifier, auditType: .contrast, elementFrame: visible, window: window))
        }
        for type: XCUIAccessibilityAuditType in [.textClipped, .dynamicType, .hitRegion, .trait, .all] {
            XCTAssertFalse(
                WelcomeAuditPolicy.shouldIgnoreAuditIssue(
                    identifier: "welcome.plan", auditType: type, elementFrame: partial, window: window))
        }
        XCTAssertFalse(
            WelcomeAuditPolicy.shouldIgnoreAuditIssue(
                identifier: "welcome.plan", auditType: [.contrast, .textClipped], elementFrame: partial, window: window)
        )
        XCTAssertFalse(
            WelcomeAuditPolicy.shouldIgnoreAuditIssue(
                identifier: nil, auditType: .contrast, elementFrame: nil, window: window))
        for identifier in ["welcome.eyebrow", "welcome.headline", "welcome.copy", "welcome.plan", "welcome.signIn"] {
            XCTAssertTrue(
                WelcomeAuditPolicy.shouldIgnoreAuditIssue(
                    identifier: identifier, auditType: .contrast, elementFrame: visible, window: window))
            XCTAssertFalse(
                WelcomeAuditPolicy.shouldIgnoreAuditIssue(
                    identifier: identifier, auditType: .textClipped, elementFrame: partial, window: window))
            XCTAssertFalse(
                WelcomeAuditPolicy.shouldIgnoreAuditIssue(
                    identifier: identifier, auditType: .contrast, elementFrame: nil, window: window))
        }
    }

    @MainActor
    func testAuditExceptionsAreLimitedToExplicitBoardContrastPairs() {
        for identifier in [
            "welcome.eyebrow", "welcome.headline", "welcome.copy", "welcome.plan", "welcome.signIn",
        ] {
            XCTAssertTrue(WelcomeAuditPolicy.isBoardContrast(identifier: identifier, auditType: .contrast))
            for type: XCUIAccessibilityAuditType in [.textClipped, .dynamicType, .hitRegion, .trait, .all] {
                XCTAssertFalse(WelcomeAuditPolicy.isBoardContrast(identifier: identifier, auditType: type))
            }
            XCTAssertFalse(
                WelcomeAuditPolicy.isBoardContrast(identifier: identifier, auditType: [.contrast, .textClipped]))
        }
        for identifier in [
            nil, "", "welcome", "welcome.wordmark", "welcome.newElement", "route.signIn",
        ] {
            XCTAssertFalse(WelcomeAuditPolicy.isBoardContrast(identifier: identifier, auditType: .contrast))
        }
    }
}
