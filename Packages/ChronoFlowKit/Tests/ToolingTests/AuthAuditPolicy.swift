import CoreGraphics

nonisolated enum AuthAuditPolicy {
    static let frameTolerance: CGFloat = 0.01

    static func isDisabledContrast(isContrast: Bool, isEnabled: Bool?) -> Bool {
        isContrast && isEnabled == false
    }

    static func contains(_ frame: CGRect?, in container: CGRect?) -> Bool {
        guard let frame, let container else { return false }
        return AuthScrollGesture.fullyVisible(frame, in: container)
    }

    static func sameFrames(_ before: [String: CGRect], _ after: [String: CGRect]) -> Bool {
        guard before.keys == after.keys else { return false }
        return before.allSatisfy { identifier, frame in
            guard let other = after[identifier], !frame.isEmpty, !frame.isInfinite,
                !other.isEmpty, !other.isInfinite
            else { return false }
            return zip(
                [frame.minX, frame.minY, frame.width, frame.height],
                [other.minX, other.minY, other.width, other.height]
            ).allSatisfy { abs($0 - $1) <= frameTolerance }
        }
    }

    static func isMeasuredSignUpBackContrast(
        identifier: String?, frame: CGRect?, backFrame: CGRect?, isContrast: Bool,
        minimum: Double?
    ) -> Bool {
        guard isContrast, identifier == "sign-up.back", let frame, let backFrame,
            let minimum, minimum.isFinite, minimum >= 4.5
        else { return false }
        return AuthAuditPolicy.contains(frame, in: backFrame)
    }

    static func isMeasuredSubtitleContrast(
        identifier: String?, isContrast: Bool, minimum: Double?
    ) -> Bool {
        guard isContrast, identifier == "auth.subtitle", let minimum else { return false }
        return minimum.isFinite && minimum >= 4.5
    }

    static func isDeferredControlContrast(
        isContrast: Bool, frame: CGRect?, viewport: CGRect, controlFrames: [CGRect]
    ) -> Bool {
        guard isContrast, let frame, !frame.isEmpty, !frame.isInfinite,
            !viewport.isEmpty, !viewport.isInfinite,
            !viewport.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
        else { return false }
        // Each scheduled control is revealed and audited in full before this screen finishes.
        return controlFrames.contains {
            !$0.isEmpty && !$0.isInfinite && $0.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
        }
    }

    static func isMeasuredBrandContrast(
        identifier: String?, frame: CGRect?, brandFrame: CGRect?, isContrast: Bool,
        minimum: Double?
    ) -> Bool {
        guard isContrast, identifier == nil || identifier == "",
            let frame, !frame.isEmpty, !frame.isInfinite,
            let brandFrame, !brandFrame.isEmpty, !brandFrame.isInfinite,
            let minimum, minimum.isFinite, minimum >= 4.5
        else { return false }
        return brandFrame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
    }

    static func isMeasuredForgotBannerContrast(
        identifier: String?, frame: CGRect?, bannerFrame: CGRect?,
        isContrast: Bool,
        state: String?, minimum: Double?
    ) -> Bool {
        guard isContrast, ["server", "throttle"].contains(state ?? ""),
            identifier == nil || identifier == "" || identifier == "auth.banner",
            let frame, !frame.isEmpty, !frame.isInfinite,
            let bannerFrame, !bannerFrame.isEmpty, !bannerFrame.isInfinite,
            let minimum
        else { return false }
        return minimum.isFinite && minimum >= 4.5
            && bannerFrame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
    }

    static func isBoardContrast(identifier: String?, isContrast: Bool) -> Bool {
        // Board boundary contrast is accepted, OQ 33 (user 2026-11-06); text ratios remain pinned.
        isContrast && identifier == "sign-in.guest"
    }
}
