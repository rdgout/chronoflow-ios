import UIKit
import XCTest

@MainActor
final class LaunchTestHost {
    let window: UIWindow
    private let previousKeyWindow: UIWindow?

    init(controller: UIViewController, style: UIUserInterfaceStyle) throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.isHidden = false
        controller.loadViewIfNeeded()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }

    static func storyboardController() throws -> UIViewController {
        try XCTUnwrap(UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController())
    }

    static func moon(in view: UIView) throws -> UIImageView {
        XCTAssertEqual(view.subviews.count, 1)
        return try XCTUnwrap(view.subviews.first as? UIImageView)
    }

    static func imageTraits(style: UIUserInterfaceStyle, scale: CGFloat) -> UITraitCollection {
        UITraitCollection {
            $0.userInterfaceStyle = style
            $0.displayScale = scale
        }
    }

    static func pixels(of image: UIImage, traits: UITraitCollection) throws -> [UInt8] {
        let resolved = image.imageAsset?.image(with: traits) ?? image
        // An unattached image view can reselect a catalog variant; freeze the resolved bitmap first.
        let bitmap = UIImage(
            cgImage: try XCTUnwrap(resolved.cgImage), scale: resolved.scale, orientation: resolved.imageOrientation)
        let reference = UIImageView(image: bitmap)
        reference.contentMode = .center
        reference.bounds = CGRect(origin: .zero, size: bitmap.size)
        reference.layoutIfNeeded()
        return try pixels(of: reference, scale: traits.displayScale)
    }

    static func assertMoonImage(
        _ moon: UIImageView, matches expected: UIImage, traits: UITraitCollection,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(moon.traitCollection.userInterfaceStyle, traits.userInterfaceStyle, file: file, line: line)
        XCTAssertEqual(moon.traitCollection.displayScale, traits.displayScale, file: file, line: line)
        let selected = try XCTUnwrap(moon.image, file: file, line: line)
        let actualPixels = try pixels(of: selected, traits: moon.traitCollection)
        let expectedPixels = try pixels(of: expected, traits: traits)
        assertPixelsEqual(
            actualPixels, expectedPixels, width: Int((expected.size.width * traits.displayScale).rounded()),
            style: traits.userInterfaceStyle, context: "Resolved moon image", file: file, line: line)
    }

    static func pixelDifference(_ actual: [UInt8], _ expected: [UInt8], width: Int) -> (
        maximum: Int, firstMismatch: String?
    ) {
        var maximum = 0
        var firstMismatch: String?
        for (index, values) in zip(actual, expected).enumerated() {
            let difference = abs(Int(values.0) - Int(values.1))
            maximum = max(maximum, difference)
            if difference > 2 && firstMismatch == nil {
                let pixel = index / 4
                let channel = ["R", "G", "B", "A"][index % 4]
                firstMismatch =
                    "(x: \(pixel % width), y: \(pixel / width)), channel \(channel), "
                    + "actual \(values.0), expected \(values.1)"
            }
        }
        return (maximum, firstMismatch)
    }

    static func assertPixelsEqual(
        _ actual: [UInt8], _ expected: [UInt8], width: Int, style: UIUserInterfaceStyle, context: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let appearance = style == .dark ? "dark" : "light"
        XCTAssertEqual(actual.count, expected.count, "\(context), style \(appearance)", file: file, line: line)
        guard actual.count == expected.count else { return }
        let difference = pixelDifference(actual, expected, width: width)
        XCTAssertLessThanOrEqual(
            difference.maximum, 2,
            "\(context) channel error (bytes), style \(appearance); "
                + "first differing pixel: \(difference.firstMismatch ?? "none")",
            file: file, line: line)
    }

    static func pixels(of view: UIView, scale: CGFloat) throws -> [UInt8] {
        let width = Int((view.bounds.width * scale).rounded())
        let height = Int((view.bounds.height * scale).rounded())
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        var data = [UInt8](repeating: 0, count: width * height * 4)
        try data.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(
                CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            view.layer.render(in: context)
        }
        return data
    }
}
