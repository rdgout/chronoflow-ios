import CoreText
import Testing

@testable import DesignSystem

@Test func everyFontResolvesAfterRegistration() async throws {
    try await FontRegistry.register()
    try await FontRegistry.register()
    for face in FontFace.allCases {
        let font = CTFontCreateWithName(face.rawValue as CFString, 20, nil)
        #expect(CTFontCopyPostScriptName(font) as String == face.rawValue)
        #expect(CTFontCopyVariationAxes(font) == nil)
    }
}

@Test @MainActor func typographyMatchesTheSpec() {
    #expect(Typography.splashWordmark.relativeTo == nil)
    let styles: [(Typography.Style, FontFace, Double, Double?, Double)] = [
        (Typography.splashWordmark, .fraunces400Opsz32, 32, 40, -0.32),
        (Typography.status, .figtree400, 14, 20, 0),
        (Typography.welcomeWordmark, .fraunces400Opsz20, 20, 28, -0.20),
        (Typography.eyebrow, .figtree600, 12, 16, 1.2),
        (Typography.headline, .fraunces400Opsz48, 48, 48, -0.48),
        (Typography.copy, .figtree400, 16, 24, 0),
        (Typography.primaryButton, .figtree600, 16, nil, 0),
        (Typography.secondaryButton, .figtree500, 16, nil, 0),
    ]
    for (style, face, size, lineHeight, tracking) in styles {
        #expect(style.face == face)
        #expect(style.size == size)
        #expect(style.lineHeight == lineHeight)
        #expect(abs(style.tracking - tracking) < 0.00001)
    }
}

#if canImport(UIKit)
    import UIKit

    @Test @MainActor func uiFontsUseTheExactFacesAndKeepTheSplashFixed() async throws {
        try await FontRegistry.register()
        let normal = UITraitCollection(preferredContentSizeCategory: .large)
        let smaller = UITraitCollection(preferredContentSizeCategory: .small)
        let larger = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let styles: [(Typography.Style, UIFont.TextStyle?)] = [
            (Typography.splashWordmark, nil),
            (Typography.status, .subheadline),
            (Typography.welcomeWordmark, .title3),
            (Typography.eyebrow, .caption1),
            (Typography.headline, .largeTitle),
            (Typography.copy, .body),
            (Typography.primaryButton, .body),
            (Typography.secondaryButton, .body),
        ]
        for (style, textStyle) in styles {
            let base = try #require(UIFont(name: style.face.rawValue, size: style.size))
            for scale in [CGFloat(2), CGFloat(3)] {
                for categoryTraits in [smaller, normal, larger] {
                    let traits = categoryTraits.modifyingTraits { $0.displayScale = scale }
                    let font = style.uiFont(compatibleWith: traits)
                    #expect(font.fontName == style.face.rawValue)
                    if let textStyle, categoryTraits != normal {
                        let expected = UIFontMetrics(forTextStyle: textStyle).scaledFont(
                            for: base, compatibleWith: traits)
                        #expect(font.pointSize == expected.pointSize)
                        if categoryTraits == smaller {
                            #expect(font.pointSize < CGFloat(style.size))
                        } else {
                            #expect(font.pointSize > CGFloat(style.size))
                        }
                    } else {
                        #expect(font.pointSize == CGFloat(style.size))
                    }
                }
            }
        }
    }
#endif
