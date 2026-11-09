import Testing

@testable import DesignSystem

#if canImport(UIKit)
    import UIKit
#endif

@Suite struct LaunchImagesTests {
    #if canImport(UIKit)

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

        @Test @MainActor func launchWordmarkResolvesAtDeviceScale() throws {
            let scale = UIScreen.main.scale
            var renditions: [Data] = []
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection {
                    $0.userInterfaceStyle = style
                    $0.displayScale = scale
                }
                let image = LaunchImages.wordmark(compatibleWith: traits)
                let bitmap = try #require(image.cgImage)
                #expect(image.size.height == CGFloat(40))
                #expect(image.size.width > 0)
                #expect(image.scale == scale)
                #expect(bitmap.width == Int(image.size.width * scale))
                #expect(bitmap.height == Int(40 * scale))
                renditions.append(try #require(bitmap.dataProvider?.data) as Data)
            }
            #expect(renditions[0] != renditions[1])
        }
    #endif
}
