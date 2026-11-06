import XCTest

@MainActor enum WelcomeAuditPolicy {
    @MainActor
    static func isFullyVisible(_ frame: CGRect, in window: CGRect) -> Bool {
        !frame.isEmpty && window.contains(frame)
    }

    @MainActor
    static var welcomeAuditTypes: XCUIAccessibilityAuditType { .all.subtracting(.dynamicType) }

    @MainActor
    static func shouldIgnoreAuditIssue(
        identifier: String?, auditType: XCUIAccessibilityAuditType, elementFrame: CGRect?, window: CGRect
    ) -> Bool {
        guard auditType == .contrast, let elementFrame else { return false }
        return isBoardContrast(identifier: identifier, auditType: auditType)
            || !isFullyVisible(elementFrame, in: window)
    }

    @MainActor
    static func isBoardContrast(identifier: String?, auditType: XCUIAccessibilityAuditType) -> Bool {
        guard auditType == .contrast else { return false }
        switch identifier {
        case "welcome.eyebrow", "welcome.headline", "welcome.copy", "welcome.plan", "welcome.signIn":
            return true
        default:
            return false
        }
    }

}
