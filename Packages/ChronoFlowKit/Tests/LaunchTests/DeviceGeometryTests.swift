import AppCore
import CoreText
import DesignSystem
import Foundation
import Launch
import SnapshotSupport
import Testing

@Suite struct DeviceGeometryTests {
    @Test func tableIncludesEveryDeviceAtItsOwnScaleAndInsets() throws {
        let devices = try SnapshotDevice.all()
        #expect(Set(devices.map(\.alias)) == ["se", "17e", "17", "air", "18pro", "18promax", "duo"])
        let se = try #require(devices.first { $0.alias == "se" })
        #expect(se.size == CGSize(width: 375, height: 667) && se.scale == 2 && se.insets.bottom == 0)
        let duo = try #require(devices.first { $0.alias == "duo" })
        #expect(duo.insets.right == 19 && duo.insets.left == 0 && duo.scale == 3)
    }

    @Test func statusTextAndDotsKeepTheirBoardSpacingAndPixelAlignedWidth() {
        let layout = StatusLineLayout(width: 390, textWidth: 150.1, ascent: 12, descent: 3, lineHeight: 20, scale: 2)
        #expect(layout.text == CGRect(x: 107.75, y: 2.5, width: 150.5, height: 20))
        #expect(layout.dots.minX - layout.text.maxX == 6)
        #expect(layout.dots.width == 18)
        #expect(layout.ink.maxX + layout.ink.minX == 390)
    }

    @Test func sampledInkIsContainedAndCompositionKeepsBoardClearances() async throws {
        try await FontRegistry.register()
        let wordmark = Typography.splashWordmark
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): wordmark.coreTextFont,
            .init(kCTKernAttributeName as String): wordmark.tracking,
        ]
        let width = CGFloat(
            CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(NSAttributedString(string: "ChronoFlow", attributes: attributes)), nil,
                nil, nil))
        for device in try SnapshotDevice.all() {
            for insets in [device.insets, .init(top: 7, left: 19, bottom: 11, right: 31)] {
                let size = device.size
                let layout = LaunchLayout(size: size, safeAreaInsets: insets)
                for frame in LaunchSnapshotCase.all {
                    let values = frame.timeline(size: size, safeInsets: insets).sample(
                        at: .milliseconds(frame.milliseconds))
                    func scalar(_ id: LayerID, _ key: String, default fallback: Double = 1) -> CGFloat {
                        guard case .scalar(let value) = values[id]?[key] else { return fallback }
                        return value
                    }
                    guard scalar(.container, "opacity") > 0 else { continue }
                    let rootScale = scalar(.container, "transform.scale")
                    func rect(_ centre: CGPoint, width: CGFloat, height: CGFloat) -> CGRect {
                        CGRect(
                            x: size.width / 2 + (centre.x - size.width / 2 - width / 2) * rootScale,
                            y: size.height * 0.4 + (centre.y - size.height * 0.4 - height / 2) * rootScale,
                            width: width * rootScale, height: height * rootScale)
                    }
                    if case .point(let centre) = values[.moon]?["position"] {
                        let glyph = rect(
                            centre, width: 104 * scalar(.moon, "transform.scale"),
                            height: 104 * scalar(.moon, "transform.scale"))
                        #expect(
                            layout.safeBounds.insetBy(dx: -0.5, dy: -0.5).contains(glyph),
                            "\(device.alias) \(frame.name) \(glyph)")
                    }
                    if scalar(.wordmark, "opacity", default: 0) > 0 {
                        let mark = rect(
                            .init(
                                x: layout.wordmarkCentre.x,
                                y: layout.wordmarkCentre.y + scalar(.wordmark, "transform.translation.y", default: 0)),
                            width: width, height: 40)
                        #expect(layout.safeBounds.contains(mark))
                    }
                    if scalar(.sun, "opacity", default: 0) > 0 {
                        let sun = rect(
                            .init(
                                x: layout.sunCentre.x,
                                y: layout.sunCentre.y + scalar(.sun, "transform.translation.y", default: 0)),
                            width: 180, height: 180)
                        let bounds = CGRect(
                            x: insets.left, y: 0, width: size.width - insets.left - insets.right, height: size.height)
                        #expect(LaunchSnapshotGeometry.containsSun(sun, in: bounds), "\(device.alias) \(frame.name)")
                    }
                }
                let apex = FlightPath(size: size).point(atFraction: 0.5).y
                #expect(abs(layout.status.minY - apex - 5.5) < 0.001)
                #expect(layout.status.maxY < layout.sunCentre.y - 90)
                #expect(layout.wordmarkCentre.y + 20 < apex)
                for language in ["Getting your plan ready", "Je plan wordt klaargezet"] {
                    for fontSize in [Typography.status.size, Typography.status.size * 1.5] {
                        let font = CTFontCreateWithName(Typography.status.face.rawValue as CFString, fontSize, nil)
                        let text = NSAttributedString(
                            string: language, attributes: [.init(kCTFontAttributeName as String): font])
                        var ascent: CGFloat = 0
                        var descent: CGFloat = 0
                        let textWidth = CTLineGetTypographicBounds(
                            CTLineCreateWithAttributedString(text), &ascent, &descent, nil)
                        let status = StatusLineLayout(
                            width: size.width, textWidth: textWidth, ascent: ascent, descent: descent,
                            lineHeight: Typography.status.lineHeight! * fontSize / Typography.status.size,
                            scale: device.scale)
                        let ink = status.ink.offsetBy(dx: 0, dy: layout.status.minY)
                        #expect(layout.safeBounds.contains(ink), "\(device.alias) \(language)")
                    }
                }
            }
        }
    }
}
