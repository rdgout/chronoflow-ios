import CoreText
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

public enum Typography {
    public struct Style: Sendable, Equatable {
        public let face: FontFace
        public let size: Double
        public let lineHeight: Double?
        public let tracking: Double
        public let relativeTo: Font.TextStyle?

        public var font: Font {
            if let relativeTo {
                .custom(face.rawValue, size: size, relativeTo: relativeTo)
            } else {
                .custom(face.rawValue, fixedSize: size)
            }
        }

        public var coreTextFont: CTFont { CTFontCreateWithName(face.rawValue as CFString, size, nil) }

        #if canImport(UIKit)
            public func uiFont(compatibleWith traits: UITraitCollection) -> UIFont {
                let traits = ContentSizeCap.traits(traits)
                let base = UIFont(name: face.rawValue, size: size)!
                guard let relativeTo else { return base }
                // Metrics can perturb the design size even at the default category.
                guard traits.preferredContentSizeCategory != .large else { return base }
                let textStyle: UIFont.TextStyle =
                    switch relativeTo {
                    case .largeTitle: .largeTitle
                    case .title: .title1
                    case .title2: .title2
                    case .title3: .title3
                    case .headline: .headline
                    case .subheadline: .subheadline
                    case .footnote: .footnote
                    case .caption: .caption1
                    case .caption2: .caption2
                    default: .body
                    }
                return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base, compatibleWith: traits)
            }
        #endif
    }

    public static var planCardTitle: Style {
        Style(face: .fraunces400Opsz20, metrics: PlanTypeMetrics.planCardTitle, relativeTo: .title2)
    }
    public static var planDayTitle: Style {
        Style(face: .fraunces400Opsz20, metrics: PlanTypeMetrics.planDayTitle, relativeTo: .title3)
    }
    public static var planRemoteTitle: Style {
        Style(face: .fraunces400Opsz20, metrics: PlanTypeMetrics.planRemoteTitle, relativeTo: .title2)
    }

    public static var planTitle: Style {
        Style(face: PlanTypeMetrics.planTitleFace, metrics: PlanTypeMetrics.planTitle, relativeTo: .headline)
    }
    public static var planSubtitle: Style {
        Style(face: PlanTypeMetrics.planSubtitleFace, metrics: PlanTypeMetrics.planSubtitle, relativeTo: .caption)
    }
    public static var planLane: Style {
        Style(face: PlanTypeMetrics.planLaneFace, metrics: PlanTypeMetrics.planLane, relativeTo: .caption2)
    }
    public static var planCompactDate: Style {
        Style(
            face: PlanTypeMetrics.planCompactDateFace, metrics: PlanTypeMetrics.planCompactDate, relativeTo: .caption2)
    }
    public static var planListLine: Style {
        Style(face: PlanTypeMetrics.planListLineFace, metrics: PlanTypeMetrics.planListLine, relativeTo: .subheadline)
    }

    public static var splashWordmark: Style {
        Style(face: .fraunces400Opsz32, metrics: .splashWordmark, relativeTo: nil)
    }
    public static var status: Style { Style(face: .figtree400, metrics: .body, relativeTo: .subheadline) }
    public static var welcomeWordmark: Style {
        Style(face: .fraunces400Opsz20, metrics: .sectionTitle, relativeTo: .title3)
    }
    public static var eyebrow: Style { Style(face: .figtree600, metrics: .eyebrow, relativeTo: .caption) }
    public static var headline: Style { Style(face: .fraunces400Opsz48, metrics: .hero, relativeTo: .largeTitle) }
    public static var copy: Style { Style(face: .figtree400, metrics: .bodyLg, relativeTo: .body) }
    public static var primaryButton: Style { Style(face: .figtree600, metrics: .button, relativeTo: .body) }
    public static var secondaryButton: Style { Style(face: .figtree500, metrics: .button, relativeTo: .body) }
}

extension Typography.Style {
    fileprivate init(face: FontFace, metrics: TypeMetrics, relativeTo: Font.TextStyle?) {
        self.face = face
        size = metrics.size
        lineHeight = metrics.lineHeight
        tracking = metrics.tracking
        self.relativeTo = relativeTo
    }
}
