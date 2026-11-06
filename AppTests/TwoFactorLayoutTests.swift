import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class TwoFactorLayoutTests: XCTestCase {
    @MainActor func testModesAndErrorsRespectEveryProfilesSafeInsetsAndTouchTargets() async throws {
        try await FontRegistry.register()
        for fixture in try AuthDeviceFixture.all() {
            for language in ["en", "nl"] {
                for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                    for recovery in [false, true] {
                        for state in TwoFactorSnapshotState.allCases {
                            var frames: [AuthElement: CGRect] = [:]
                            let host = try AuthTestHost(
                                TwoFactorView(model: twoFactorSnapshotModel(recovery: recovery, state: state)) {
                                    frames[$0] = $1
                                }, size: fixture.size, insets: fixture.insets, language: language, category: category,
                                scale: fixture.scale)
                            defer { host.close() }
                            try await host.settle()
                            XCTAssertEqual(Set(frames.keys), [.brand, .heading, .card, .code, .submit, .modeToggle])
                            let brand = try XCTUnwrap(frames[.brand])
                            XCTAssertEqual(brand.minY, fixture.insets.top + AuthTokens.gutter, accuracy: 0.5)
                            for frame in frames.values {
                                XCTAssertGreaterThan(frame.height, 0)
                                XCTAssertGreaterThanOrEqual(frame.minX, fixture.insets.left + AuthTokens.gutter - 0.5)
                                XCTAssertLessThanOrEqual(
                                    frame.maxX, fixture.size.width - fixture.insets.right - AuthTokens.gutter + 0.5)
                            }
                            for element in [AuthElement.code, .submit, .modeToggle] {
                                XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[element]).height, AuthTokens.touch)
                            }
                            XCTAssertLessThan(try XCTUnwrap(frames[.heading]).maxY, try XCTUnwrap(frames[.card]).minY)
                            XCTAssertLessThanOrEqual(
                                try XCTUnwrap(frames[.code]).maxY, try XCTUnwrap(frames[.submit]).minY)
                            XCTAssertLessThanOrEqual(
                                try XCTUnwrap(frames[.submit]).maxY, try XCTUnwrap(frames[.modeToggle]).minY)
                        }
                    }
                }
            }
        }
    }
}
