#if DEBUG
    import AppCore
    import DesignSystem
    import PlanUI
    import SwiftUI
    import XCTest

    nonisolated final class TripActionsLayoutTests: XCTestCase {
        override func setUp() {
            super.setUp()
            executionTimeAllowance = 60
        }

        @MainActor func testSEAtXXLarge() async throws { try await check("se") }
        @MainActor func testDuoWithAsymmetricRailAtXXLarge() async throws { try await check("duo-asymmetric") }

        @MainActor private func check(_ name: String) async throws {
            try await AuthTestHost.registerFonts()
            let profile = try XCTUnwrap(try AuthDeviceFixture.layoutStressProfiles().first { $0.name == name })
            let account = try PlanScreenFixture.account()
            let card = account.trips[0].card
            let content = PlanMeasuredContent()
            let host = try AuthTestHost(
                TripActionsSheet(card: card, detail: account.details[card.id], online: false, onAction: { _ in })
                    .capturePlanContent(in: content),
                size: profile.size, insets: profile.insets, language: "nl", category: .extraExtraLarge,
                scale: profile.scale)
            defer { host.close() }
            try await host.settleLayout { content.frames }
            let frame = try XCTUnwrap(content.frames.first)
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThanOrEqual(frame.minX, profile.insets.left - 1 / profile.scale)
            XCTAssertLessThanOrEqual(frame.maxX, profile.size.width - profile.insets.right + 1 / profile.scale)
        }
    }

    nonisolated class TripActionsSnapshotTests: XCTestCase {
        var profileName: String { "17e" }
        override func setUp() {
            super.setUp()
            executionTimeAllowance = 60
        }

        @MainActor func testWithPlan() async throws { try await capture(noPlan: false) }
        @MainActor func testWithoutPlan() async throws { try await capture(noPlan: true) }
        @MainActor func testOffline() async throws { try await capture(noPlan: false, online: false) }

        @MainActor private func capture(noPlan: Bool, online: Bool = true) async throws {
            try await AuthTestHost.registerFonts()
            let profile = try XCTUnwrap(try AuthDeviceFixture.all().first { $0.name == profileName })
            let account = try PlanScreenFixture.account()
            let card = account.trips[0].card
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    let host = try AuthTestHost(
                        TripActionsSheet(
                            card: card, detail: noPlan ? nil : account.details[card.id], online: online,
                            onAction: { _ in }),
                        size: profile.size, insets: profile.insets, style: style, language: language,
                        category: .extraExtraLarge, scale: profile.scale)
                    defer { host.close() }
                    try await host.settle()
                    let attachment = XCTAttachment(image: try host.image())
                    attachment.name =
                        "TripActions-\(profile.snapshotName)-\(language)-\(style.rawValue)-\(noPlan)-\(online)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    nonisolated final class TripActionsSESnapshotTests: TripActionsSnapshotTests {
        override var profileName: String { "se" }
    }
    nonisolated final class TripActions17SnapshotTests: TripActionsSnapshotTests {
        override var profileName: String { "17" }
    }
    nonisolated final class TripActionsAirSnapshotTests: TripActionsSnapshotTests {
        override var profileName: String { "air" }
    }
    nonisolated final class TripActions18ProSnapshotTests: TripActionsSnapshotTests {
        override var profileName: String { "18pro" }
    }
    nonisolated final class TripActions18ProMaxSnapshotTests: TripActionsSnapshotTests {
        override var profileName: String { "18promax" }
    }
    nonisolated final class TripActionsDuoSnapshotTests: TripActionsSnapshotTests {
        override var profileName: String { "duo" }
    }
#endif
