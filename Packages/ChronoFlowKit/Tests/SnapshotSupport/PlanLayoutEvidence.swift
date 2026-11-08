import CoreGraphics
import Foundation

public nonisolated enum PlanLayoutEvidence {
    public static func contentViewport(
        scroll: CGRect, top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat
    ) -> CGRect {
        CGRect(
            x: scroll.minX + left, y: scroll.minY + top,
            width: max(0, scroll.width - left - right), height: max(0, scroll.height - top - bottom))
    }

    public static func passingText(
        issueIdentifier: String?, issueFrame: CGRect?, identifier: String, frame: CGRect, minimum: Double?
    ) -> Bool {
        guard let minimum, minimum.isFinite, minimum >= 4.5 else { return false }
        return attributedText(
            issueIdentifier: issueIdentifier, issueFrame: issueFrame, identifier: identifier, frame: frame)
    }

    public static func attributedText(
        issueIdentifier: String?, issueFrame: CGRect?, identifier: String, frame: CGRect
    ) -> Bool {
        guard identifier.hasPrefix("plan.text.") || identifier == "legend.close",
            issueIdentifier == identifier || issueIdentifier == nil || issueIdentifier == "",
            let issueFrame, valid(issueFrame), valid(frame)
        else { return false }
        return frame.insetBy(dx: -0.01, dy: -0.01).contains(issueFrame)
    }

    private static func valid(_ frame: CGRect) -> Bool {
        !frame.isEmpty && !frame.isNull && !frame.isInfinite
            && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
    }
}
