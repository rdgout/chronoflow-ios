#if canImport(UIKit)
    import UIKit

    public enum LaunchImages {
        public static func moon(compatibleWith traits: UITraitCollection) -> UIImage {
            guard let image = UIImage(named: "LaunchMoon", in: .module, compatibleWith: traits) else {
                preconditionFailure("Missing generated LaunchMoon asset")
            }
            return image
        }
    }
#endif
