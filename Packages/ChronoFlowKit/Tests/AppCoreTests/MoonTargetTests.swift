import CoreGraphics
import Foundation
import Testing

@testable import AppCore

struct MoonTargetTests {
    @Test func boardTargetAndPaddingRule() {
        let size = CGSize(width: 390, height: 844)
        let insets = MoonTarget.Insets(top: 47, left: 0, bottom: 34, right: 0)
        let target = MoonTarget.fallback(size: size, safeAreaInsets: insets, rowHeight: 28)
        #expect(target == CGRect(x: 24, y: 64, width: 28, height: 28))
        #expect(target.midX == 38 && target.midY == 78)
        #expect(
            MoonTarget.contentBounds(size: size, safeAreaInsets: insets)
                == CGRect(x: 24, y: 64, width: 342, height: 740))
    }

    @Test func largerRowMovesTheCentreAndSmallRowsKeepTheMoonSize() {
        let size = CGSize(width: 390, height: 844)
        let insets = MoonTarget.Insets(top: 47, left: 0, bottom: 34, right: 0)
        for (row, centre) in [(20.0, 78.0), (28, 78), (40, 84), (56, 92), (96, 112)] {
            let target = MoonTarget.fallback(size: size, safeAreaInsets: insets, rowHeight: row)
            #expect(target.midY == CGFloat(centre))
            #expect(target.size == CGSize(width: 28, height: 28))
        }
    }

    @Test func allFourSafeInsetsDefineTheContent() {
        let size = CGSize(width: 590, height: 900)
        let insets = MoonTarget.Insets(top: 62, left: 36, bottom: 54, right: 22)
        let content = MoonTarget.contentBounds(size: size, safeAreaInsets: insets)
        #expect(content == CGRect(x: 60, y: 78, width: 484, height: 768))
        let target = MoonTarget.fallback(size: size, safeAreaInsets: insets, rowHeight: 40)
        #expect(target.midX == 74 && target.midY == 98)
        #expect(content.contains(target))
    }

    @Test func shortAndWideWindowsAndInsetsRemainInputs() {
        let sizes = [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874), CGSize(width: 590, height: 900)]
        for size in sizes {
            for insets in [
                MoonTarget.Insets(top: 20, left: 0, bottom: 0, right: 0),
                MoonTarget.Insets(top: 62, left: 32, bottom: 34, right: 18),
            ] {
                let target = MoonTarget.fallback(size: size, safeAreaInsets: insets, rowHeight: 28)
                #expect(target.midX == insets.left + 38)
                #expect(target.midY == max(insets.top + 16, 64) + 14)
                #expect(MoonTarget.contentBounds(size: size, safeAreaInsets: insets).contains(target))
            }
        }
    }
}
