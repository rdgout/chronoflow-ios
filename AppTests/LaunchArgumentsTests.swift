import AppCore
import Launch
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class LaunchArgumentsTests: XCTestCase {
    @MainActor
    func testDefaultsAndInvalidValues() {
        for arguments in [
            [], ["-cf.freezeAt"], ["-cf.freezeAt", "nan"], ["-cf.freezeAt", "-1"],
            ["-cf.freezeAt", "inf"], ["-cf.freezeAt", "60001"], ["-cf.mode", "unknown"],
        ] {
            let parsed = LaunchArguments(arguments)
            XCTAssertNil(parsed.freezeAt)
            XCTAssertNil(parsed.mode)
            XCTAssertEqual(parsed.readyAt, .milliseconds(4600))
        }
        let parsed = LaunchArguments([
            "-cf.freezeAt", "700", "-cf.mode", "slow", "-cf.readyAt", "3500",
            "-cf.mainThreadStall", "500", "-cf.reduceMotion",
        ])
        XCTAssertEqual(parsed.freezeAt, .milliseconds(700))
        XCTAssertEqual(parsed.mainThreadStall, .milliseconds(500))
        XCTAssertEqual(parsed.readyAt, .milliseconds(3500))
        XCTAssertTrue(parsed.reduceMotion)
    }

    @MainActor
    func testWelcomeFallbackUsesTheCurrentTextSizeAndAllSafeInsets() throws {
        let normal = LaunchArguments.fallbackRowHeight(
            compatibleWith: UITraitCollection {
                $0.preferredContentSizeCategory = .large
            })
        let larger = LaunchArguments.fallbackRowHeight(
            compatibleWith: UITraitCollection {
                $0.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            })
        XCTAssertEqual(normal, 28)
        XCTAssertGreaterThan(larger, normal)
        let size = CGSize(width: 570, height: 730)
        let insets = MoonTarget.Insets(top: 31, left: 37, bottom: 27, right: 59)
        let timeline = LaunchArguments(["-cf.mode", "welcome"]).timeline(
            opening: .opening(size: size, reduceMotion: false), safeAreaInsets: insets, rowHeight: larger)
        guard case .point(let target) = try XCTUnwrap(timeline.sample(at: .milliseconds(2300))[.moon]?["position"])
        else { return XCTFail("Missing moon target") }
        XCTAssertEqual(target.x, insets.left + 24 + 14)
        XCTAssertEqual(target.y, max(insets.top + 16, 64) + larger / 2)
    }

    @MainActor
    func testModeTimelinesAndAsymmetricSafeAreaFallback() {
        let size = CGSize(width: 570, height: 730)
        let opening = LaunchTimeline.opening(size: size, reduceMotion: false)
        let safe = MoonTarget.Insets(top: 23, left: 31, bottom: 29, right: 47)
        for mode in ["ready", "slow", "welcome"] {
            let arguments = LaunchArguments(["-cf.mode", mode])
            let actual = arguments.timeline(opening: opening, safeAreaInsets: safe)
            let expected: LaunchTimeline
            switch mode {
            case "ready": expected = opening.withReadyExit(at: .milliseconds(1500))
            case "slow": expected = opening.withStatus(at: .seconds(2)).withReadyExit(at: .milliseconds(4600))
            default:
                expected = opening.withWelcomeExit(
                    at: .milliseconds(1600), size: size,
                    moonTarget: MoonTarget.fallback(size: size, safeAreaInsets: safe, rowHeight: 28))
            }
            XCTAssertEqual(actual, expected)
        }
    }
}
