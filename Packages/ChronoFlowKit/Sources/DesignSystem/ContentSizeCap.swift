import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

public enum ContentSizeCap {
    public static var maximum: DynamicTypeSize { .xxLarge }

    #if canImport(UIKit)
        public static var maximumCategory: UIContentSizeCategory { UIContentSizeCategory(maximum) }

        public static func clamp(_ category: UIContentSizeCategory) -> UIContentSizeCategory {
            category > maximumCategory ? maximumCategory : category
        }

        public static func traits(_ traits: UITraitCollection) -> UITraitCollection {
            traits.modifyingTraits {
                $0.preferredContentSizeCategory = clamp(traits.preferredContentSizeCategory)
            }
        }
    #endif
}
