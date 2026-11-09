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
        for fixture in try profiles() {
            for state in [TodaySnapshotState.active, .empty, .loading] {
                try await assertRefresh(in: fixture, context: "Today \(state)") { action in
                    let feedback = RefreshFeedbackModel()
                    return AnyView(
                        try todayFixture(state, formatter: formatter) { await feedback.refresh(action: action) }
                            .planRefreshFeedback(feedback))
                }
            }
            for state in TripsSnapshotState.allCases {
                try await assertRefresh(in: fixture, context: "My trips \(state)") { action in
                    let feedback = RefreshFeedbackModel()
                    return AnyView(
                        try tripsFixture(state, formatter: formatter) { await feedback.refresh(action: action) }
                            .planRefreshFeedback(feedback))
                }
            }
        }
    }

    @MainActor func testTripPageMountsNativeRefreshInEveryState() async throws {
        try await AuthTestHost.registerFonts()
        let formatter = try await PlanScreenFixture.formatter()
        for fixture in try profiles() {
            for state in TripPageState.allCases {
                let context = try await TripSnapshotContext(state: state, language: "en")
                do {
                    try await context.wait()
                    try await assertRefresh(in: fixture, context: "Trip page \(state)") { action in
                        AnyView(TripPageView(model: context.model, formatter: formatter, refresh: action))
                    }
                } catch {
                    try await context.close()
                    throw error
                }
                try await context.close()
            }
        }
    }

    @MainActor private func profiles() throws -> [AuthDeviceFixture] {
        try AuthDeviceFixture.all().filter { ["se", "17e", "duo"].contains($0.name) }
    }

    @MainActor private func assertRefresh(
        in fixture: AuthDeviceFixture, context: String,
        screen: (@escaping () async throws -> SyncResult?) throws -> AnyView
    ) async throws {
        var calls = 0
        let completion = AsyncStream<Void>.makeStream()
        let content = try screen {
            calls += 1
            for await _ in completion.stream { break }
            return SyncResult(state: .idle, pendingCount: 0)
        }
        let host = try AuthTestHost(
            NavigationStack { content }, size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer {
            completion.continuation.finish()
            host.close()
        }
        try await host.settle()
        let context = "\(fixture.name) \(context)"
        let scroll = try XCTUnwrap(authScrollViews(host.controller.view).first, context)
        let control = try XCTUnwrap(scroll.refreshControl, context)
        XCTAssertTrue(scroll.alwaysBounceVertical, context)
        XCTAssertEqual(calls, 0, context)
        XCTAssertTrue(feedback(in: host).isEmpty, context)

        control.beginRefreshing()
        control.sendActions(for: .valueChanged)
        let started = await wait { calls == 1 }
        XCTAssertTrue(started, "Native refresh did not invoke sync: \(context)")
        XCTAssertTrue(control.isRefreshing, "Refresh must await sync: \(context)")
        XCTAssertTrue(feedback(in: host).isEmpty, context)
        completion.continuation.yield()
        completion.continuation.finish()

        let finished = await wait { !control.isRefreshing }
        XCTAssertTrue(finished, "Native refresh did not finish: \(context)")
        XCTAssertEqual(calls, 1, context)
    }

    @MainActor private func feedback(in host: AuthTestHost) -> [NSObject] {
        var visited: Set<ObjectIdentifier> = []
        func walk(_ object: NSObject) -> [NSObject] {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
            if (object as? any UIAccessibilityIdentification)?.accessibilityIdentifier == "refresh.feedback" {
                return [object]
            }
            var children = object.accessibilityElements as? [NSObject] ?? []
            let count = object.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                children += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
            }
            if let view = object as? UIView { children += view.subviews }
            return children.flatMap(walk)
        }
        return walk(host.window)
    }

    @MainActor private func wait(until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
