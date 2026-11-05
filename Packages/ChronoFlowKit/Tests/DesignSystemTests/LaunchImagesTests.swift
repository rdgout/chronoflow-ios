#if canImport(UIKit)
    import Testing
    import UIKit

    @testable import DesignSystem

    @Test @MainActor func launchMoonResolvesBothAppearancesAtDeviceScale() throws {
        // Package test runners may have no scene; thinning retains only this device's scale.
        let scale = UIScreen.main.scale
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection {
                $0.userInterfaceStyle = style
                $0.displayScale = scale
            }
            let image = LaunchImages.moon(compatibleWith: traits)
            let bitmap = try #require(image.cgImage)
            #expect(image.size == CGSize(width: 288, height: 288))
            #expect(image.scale == scale)
            #expect(bitmap.width == Int(288 * scale))
            #expect(bitmap.height == Int(288 * scale))
        }
    }
#endif
