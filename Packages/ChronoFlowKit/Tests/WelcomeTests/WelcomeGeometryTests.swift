import AppCore
import DesignSystem
import Foundation
import SnapshotSupport
import Testing
import Welcome

@Suite struct WelcomeGeometryTests {
    @Test func everyDeviceUsesAllFourInsetsAndScrollsWithoutCompressingContent() throws {
        for device in try SnapshotDevice.all() {
            for insets in [device.insets, .init(top: 7, left: 19, bottom: 11, right: 31)] {
                let geometry = WelcomeGeometry(size: device.size, insets: insets)
                #expect(geometry.content == MoonTarget.contentBounds(size: device.size, safeAreaInsets: insets))
                #expect(geometry.content.minX == insets.left + 24)
                #expect(geometry.content.maxX == device.width - insets.right - 24)
                #expect(geometry.content.minY >= insets.top + 16)
                #expect(geometry.content.maxY <= device.height - insets.bottom)
                for headingHeight in [CGFloat(276), 600, 1000] {
                    let groups = geometry.groups(headingHeight: headingHeight, actionsHeight: 300)
                    #expect(groups.actions.minY >= groups.heading.maxY + 24)
                    #expect(groups.actions.maxY >= geometry.content.maxY)
                    #expect(groups.heading.height == headingHeight)
                    #expect(groups.actions.height == 300)
                }
            }
        }
    }

    @Test func zeroInsetBoardRetainsItsComposition() {
        let geometry = WelcomeGeometry(
            size: .init(width: 390, height: 844), insets: .init(top: 0, left: 0, bottom: 0, right: 0))
        #expect(geometry.content == .init(x: 24, y: 64, width: 342, height: 740))
        let groups = geometry.groups(headingHeight: 276, actionsHeight: 296)
        #expect(groups.heading.minY == 64)
        #expect(groups.actions.maxY == 804)
        #expect(groups.actions.maxY - 52 == 752)
        #expect(groups.actions.maxY - 52 - 12 - 52 == 688)
    }
}
