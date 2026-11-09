import AppCore
import DesignSystem
import SwiftUI
import UIKit
import XCTest

@testable import Welcome

nonisolated final class SnapshotContainerTests: XCTestCase {
    @MainActor func testEveryProfileHasExplicitBoundsInsetsAndScale() async throws {
        try await FontRegistry.register()
        for device in try SnapshotDevice.all() {
            let host = WelcomeTestWindow(style: .light, device: device)
            defer { host.close() }
            try await assertFixture(host, device: device)
            // Larger parent insets must not clamp SE's top/bottom or inject a notch into Duo's side rail.
            host.container.root.additionalSafeAreaInsets = UIEdgeInsets(top: 120, left: 80, bottom: 100, right: 90)
            host.configure(style: .dark, language: "nl")
            try await assertFixture(host, device: device)
        }
    }

    @MainActor func testFreshAndReusedWelcomeHaveIdenticalPixels() async throws {
        try await FontRegistry.register()
        for device in try SnapshotDevice.all() {
            let reused = WelcomeTestWindow(style: .dark, device: device)
            defer { reused.close() }
            try await reused.layout()
            for style in [UIUserInterfaceStyle.light, .dark] {
                reused.configure(style: style, language: "nl")
                let image = try await reused.layout()
                let actual = try SnapshotRaster(image: XCTUnwrap(image.cgImage))
                let frames = reused.frames
                let fresh = WelcomeTestWindow(style: style, language: "nl", device: device)
                let reference = try await fresh.layout()
                XCTAssertTrue(actual == (try SnapshotRaster(image: XCTUnwrap(reference.cgImage))), device.alias)
                XCTAssertEqual(frames, fresh.frames, device.alias)
                fresh.close()
            }
        }
    }

    @MainActor private func assertFixture(_ host: WelcomeTestWindow, device: SnapshotDevice) async throws {
        let image = try await host.layout()
        let expected = WelcomeGeometry(size: device.size, insets: device.insets)
        XCTAssertEqual(host.window.bounds.size, device.size)
        XCTAssertEqual(host.controller.view.bounds.size, device.size)
        XCTAssertTrue(host.controller.safeAreaRegions.isEmpty)
        XCTAssertEqual(host.controller.traitCollection.displayScale, device.scale)
        let brand = try XCTUnwrap(host.frames[.brand])
        let actions = try XCTUnwrap(host.frames[.signIn])
        XCTAssertEqual(brand.minX, expected.content.minX, accuracy: 0.5)
        XCTAssertEqual(brand.minY, expected.content.minY, accuracy: 0.5)
        XCTAssertEqual(actions.minX, expected.content.minX, accuracy: 0.5)
        XCTAssertEqual(actions.maxX, expected.content.maxX, accuracy: 0.5)
        let headline = try XCTUnwrap(host.frames[.headline])
        let copy = try XCTUnwrap(host.frames[.copy])
        let groups = expected.groups(headingHeight: headline.maxY - brand.minY, actionsHeight: actions.maxY - copy.minY)
        XCTAssertEqual(actions.maxY, groups.actions.maxY, accuracy: 0.5)
        XCTAssertEqual(image.cgImage?.width, Int(device.width * device.scale))
        XCTAssertEqual(image.cgImage?.height, Int(device.height * device.scale))
        XCTAssertTrue(WelcomeSnapshotPixels.hasVisibleVariation(pixels(image)))
    }
}
