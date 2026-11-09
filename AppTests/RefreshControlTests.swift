import DesignSystem
import PlanCore
import PlanUI
import SwiftUI
import Sync
import UIKit
import XCTest

nonisolated final class RefreshControlTests: XCTestCase {
    @MainActor func testTodayAndTripsMountNativeRefreshInLoadedEmptyAndLoadingStates() async throws {
        try await AuthTestHost.registerFonts()
        let formatter = try await PlanScreenFixture.formatter()
        let screens: [AnyView] =
            try [TodaySnapshotState.active, .empty, .loading].map {
                AnyView(try todayFixture($0, formatter: formatter))
            } + TripsSnapshotState.allCases.map { AnyView(try tripsFixture($0, formatter: formatter)) }
        for fixture in try AuthDeviceFixture.all() where ["se", "17e", "duo"].contains(fixture.name) {
            for (index, screen) in screens.enumerated() {
                var calls = 0
                let completion = AsyncStream<Void>.makeStream()
                let host = try AuthTestHost(
                    NavigationStack {
                        ZStack { screen }.planRefreshable {
                            calls += 1
                            for await _ in completion.stream { break }
                            return SyncResult(state: .idle, pendingCount: 0)
                        }
                    }, size: fixture.size, insets: fixture.insets, scale: fixture.scale)
                defer {
                    completion.continuation.finish()
                    host.close()
                }
                try await host.settle()
                let context = "\(fixture.name) screen=\(index)"
                let scroll = try XCTUnwrap(authScrollViews(host.controller.view).first, context)
                let control = try XCTUnwrap(scroll.refreshControl, context)
                XCTAssertTrue(scroll.alwaysBounceVertical, context)
                let traits = host.controller.traitCollection
                XCTAssertEqual(
                    control.tintColor.resolvedColor(with: traits),
                    UIColor(ColorToken.primary.color).resolvedColor(with: traits), context)
                XCTAssertEqual(calls, 0, context)
                control.beginRefreshing()
                control.sendActions(for: .valueChanged)
                let started = await wait { calls == 1 }
                XCTAssertTrue(started, "Native refresh did not invoke sync: \(context)")
                XCTAssertTrue(control.isRefreshing, "Refresh must await sync: \(context)")
                completion.continuation.yield()
                completion.continuation.finish()
                let finished = await wait { !control.isRefreshing }
                XCTAssertTrue(finished, "Native refresh did not finish: \(context)")
                XCTAssertEqual(calls, 1, context)
            }
        }
    }

    @MainActor private func wait(until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
