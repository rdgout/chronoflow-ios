#if DEBUG
    import DesignSystem
    import PlanUI
    import SwiftUI
    import UIKit
    import XCTest

    nonisolated final class TripsLayoutTests: XCTestCase {
        @MainActor func testListAtXXLarge() async throws { try await checkTripsLayout(.list) }
    }

    nonisolated final class TripsEmptyLayoutTests: XCTestCase {
        @MainActor func testEmptyAtXXLarge() async throws { try await checkTripsLayout(.empty) }
    }

    nonisolated final class TripsLoadingLayoutTests: XCTestCase {
        @MainActor func testLoadingAtXXLarge() async throws { try await checkTripsLayout(.loading) }
    }

    @MainActor private func checkTripsLayout(_ state: TripsSnapshotState) async throws {
        try await AuthTestHost.registerFonts()
        let formatter = try await PlanScreenFixture.formatter()
        let fixtures = try AuthDeviceFixture.layoutStressProfiles()
        for fixture in fixtures where fixture.name == "se" || state == .list {
            let screen = try tripsFixture(state, formatter: formatter)
            let content = PlanMeasuredContent()
            let host = try AuthTestHost(
                NavigationStack { screen }.capturePlanContent(in: content), size: fixture.size,
                insets: fixture.insets, language: "nl", category: .extraExtraLarge, scale: fixture.scale,
                sideInsetsOutsideView: true)
            defer { host.close() }
            try await host.settleLayout { content.frames }
            try await assertPlanScrollFits(host, content: content, horizontalGutter: PlanUITokens.space4)
        }
    }
#endif
