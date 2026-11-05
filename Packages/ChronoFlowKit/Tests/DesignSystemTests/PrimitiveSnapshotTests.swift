#if canImport(UIKit)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DesignSystem

    @Suite(.serialized) @MainActor struct PrimitiveSnapshotTests {
        @Test func lightAndDarkPrimitives() {
            for appearance in TokenAppearance.allCases {
                for width in [240.0, 560.0] {
                    let controller = UIHostingController(
                        rootView: PrimitiveFixture().environment(\.colorScheme, appearance == .light ? .light : .dark))
                    let size = CGSize(width: width, height: 320)
                    controller.view.frame = CGRect(origin: .zero, size: size)
                    controller.view.layoutIfNeeded()
                    assertSnapshot(
                        of: controller, as: .image(size: size, traits: UITraitCollection(displayScale: 3)),
                        named: "\(appearance.rawValue)-\(Int(width))")
                }
            }
        }
    }

    private struct PrimitiveFixture: View {
        var body: some View {
            ZStack {
                CfSky()
                PatternDots().opacity(0.2)
                MoonShape().stroke(
                    ColorToken.dawn.color, style: StrokeStyle(lineWidth: 2 * 28 / 24, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 28, height: 28)
            }
        }
    }
#endif
