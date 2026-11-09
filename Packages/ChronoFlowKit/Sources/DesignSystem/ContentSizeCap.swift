import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

public enum ContentSizeCap {
    public static var maximum: DynamicTypeSize { .xxLarge }

    public static func clamp(_ size: DynamicTypeSize) -> DynamicTypeSize { min(size, maximum) }

    #if canImport(UIKit)
        public static var maximumCategory: UIContentSizeCategory { UIContentSizeCategory(maximum) }

        public static func apply(to controller: UIViewController, in window: UIWindow) {
            window.maximumContentSizeCategory = maximumCategory
            controller.traitOverrides.preferredContentSizeCategory = clamp(
                window.traitCollection.preferredContentSizeCategory)
            // Native text layout also reads UIKit traits, outside SwiftUI's environment cap.
            window.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
                [weak controller] (window: UIWindow, _: UITraitCollection) in
                controller?.traitOverrides.preferredContentSizeCategory = clamp(
                    window.traitCollection.preferredContentSizeCategory)
            }
        }

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
