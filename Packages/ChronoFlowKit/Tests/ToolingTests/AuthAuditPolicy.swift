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
}
