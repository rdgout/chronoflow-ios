import SwiftUI

nonisolated public struct MoonShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        Path(MoonGlyph.path).applying(
            CGAffineTransform(
                a: rect.width / MoonGlyph.viewBox, b: 0, c: 0, d: rect.height / MoonGlyph.viewBox, tx: rect.minX,
                ty: rect.minY))
    }
}
