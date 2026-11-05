#if canImport(UIKit)
    import DesignSystem
    import UIKit

    public final class LaunchFrameView: UIView {
        public init(frame: CGRect = .zero, traits: UITraitCollection) {
            let appearance: TokenAppearance = traits.userInterfaceStyle == .dark ? .dark : .light
            let moon = UIImageView(image: LaunchImages.moon(compatibleWith: traits))
            super.init(frame: frame)
            overrideUserInterfaceStyle = appearance == .dark ? .dark : .light
            backgroundColor = UIColor(cgColor: ColorToken.skyTop.components(for: appearance).cgColor)
            isOpaque = true
            clipsToBounds = true
            moon.contentMode = .center
            moon.layer.minificationFilter = .trilinear
            moon.translatesAutoresizingMaskIntoConstraints = false
            addSubview(moon)
            NSLayoutConstraint.activate([
                moon.centerXAnchor.constraint(equalTo: centerXAnchor),
                moon.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { return nil }
    }
#endif
