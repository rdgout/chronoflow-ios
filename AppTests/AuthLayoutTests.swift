import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class AuthLayoutTests: XCTestCase {
    @MainActor func testSafeAreaFixturesAreAppliedAndAllContentStaysInsideHorizontalBounds() async throws {
        try await FontRegistry.register()
        for fixture in try AuthDeviceFixture.all() {
            for language in ["en", "nl"] {
                for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                    var frames: [AuthElement: CGRect] = [:]
                    let model = authSnapshotModel()
                    model.form.receive(snapshotFailure(.credentials))
                    let host = try AuthTestHost(
                        SignInView(model: model, back: {}, guest: {}, measure: { frames[$0] = $1 }), size: fixture.size,
                        insets: fixture.insets, language: language, category: category, scale: fixture.scale)
                    defer { host.close() }
                    try await host.settle()
                    XCTAssertEqual(frames.count, AuthElement.allCases.count)
                    let brand = try XCTUnwrap(frames[.brand])
                    XCTAssertEqual(brand.minY, fixture.insets.top + AuthTokens.gutter, accuracy: 0.5)
                    XCTAssertEqual(brand.minX, fixture.insets.left + AuthTokens.gutter, accuracy: 0.5)
                    XCTAssertEqual(
                        brand.maxX, fixture.size.width - fixture.insets.right - AuthTokens.gutter, accuracy: 0.5)
                    for frame in frames.values {
                        XCTAssertGreaterThanOrEqual(frame.minX, fixture.insets.left + AuthTokens.gutter - 0.5)
                        XCTAssertLessThanOrEqual(
                            frame.maxX, fixture.size.width - fixture.insets.right - AuthTokens.gutter + 0.5)
                        XCTAssertGreaterThan(frame.height, 0)
                    }
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[.submit]).height, AuthTokens.touch)
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[.footer]).height, AuthTokens.footerHeight)
                    XCTAssertLessThan(try XCTUnwrap(frames[.heading]).maxY, try XCTUnwrap(frames[.card]).minY)
                }
            }
        }
    }
}
