import CoreGraphics
import SwiftUI

extension TokenRGBA {
    nonisolated public var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
            components: [red, green, blue, alpha].map { CGFloat($0) })!
    }

    nonisolated public var color: Color { Color(.displayP3, red: red, green: green, blue: blue, opacity: alpha) }
}

extension ColorToken {
    public var color: Color { Color(rawValue, bundle: .module) }
}
