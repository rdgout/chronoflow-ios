#if DEBUG
    import DesignSystem
    import PlanUI
    import SwiftUI
    import UIKit
    import XCTest

    nonisolated final class TodayLayoutTests: XCTestCase {
        @MainActor func testActiveAtXXLarge() async throws { try await checkTodayLayout(.active) }
    }

    nonisolated final class TodayEmptyLayoutTests: XCTestCase {
        @MainActor func testEmptyAtXXLarge() async throws { try await checkTodayLayout(.empty) }
    }

    nonisolated final class TodayFutureLayoutTests: XCTestCase {
        @MainActor func testFutureAtXXLarge() async throws { try await checkTodayLayout(.future) }
    }

    nonisolated final class TodayLoadingLayoutTests: XCTestCase {
        @MainActor func testLoadingAtXXLarge() async throws { try await checkTodayLayout(.loading) }
    }

    nonisolated final class TodayCompletedLayoutTests: XCTestCase {
        @MainActor func testCompletedAtXXLarge() async throws { try await checkTodayLayout(.completed) }
    }

    nonisolated final class TodayDoneLayoutTests: XCTestCase {
        @MainActor func testDoneAtXXLarge() async throws { try await checkTodayLayout(.done) }
    }

    nonisolated final class TodaySkippedLayoutTests: XCTestCase {
        @MainActor func testSkippedAtXXLarge() async throws { try await checkTodayLayout(.skipped) }
    }

    nonisolated final class TodayHiddenLayoutTests: XCTestCase {
        @MainActor func testHiddenAtXXLarge() async throws { try await checkTodayLayout(.hidden) }
    }

    nonisolated final class TodayAllHiddenLayoutTests: XCTestCase {
        @MainActor func testAllHiddenAtXXLarge() async throws { try await checkTodayLayout(.allHidden) }
    }

    nonisolated final class TodayNothingNowLayoutTests: XCTestCase {
        @MainActor func testNothingNowAtXXLarge() async throws { try await checkTodayLayout(.nothingNow) }
    }

    @MainActor private func checkTodayLayout(_ state: TodaySnapshotState) async throws {
        try await AuthTestHost.registerFonts()
        let formatter = try await PlanScreenFixture.formatter()
        let fixtures = try AuthDeviceFixture.layoutStressProfiles()
        for fixture in fixtures where fixture.name == "se" || state == .active {
            let screen = try todayFixture(state, formatter: formatter)
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
