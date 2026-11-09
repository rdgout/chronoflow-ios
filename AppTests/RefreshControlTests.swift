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

    @MainActor func testReplacementFeedbackKeepsItsOwnTwoSecondLifetime() async throws {
        try await AuthTestHost.registerFonts()
        let fixture = try XCTUnwrap(profiles().first { $0.name == "17e" })
        let formatter = try await PlanScreenFixture.formatter()
        let model = RefreshFeedbackModel()
        let screen = try todayFixture(.active, formatter: formatter) {}
        let host = try AuthTestHost(
            NavigationStack { screen.planRefreshFeedback(model) },
            size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer { host.close() }
        try await host.settle()
        await model.refresh { SyncResult(state: .idle, pendingCount: 0) }
        let first = await wait { self.feedback(in: host).first?.accessibilityLabel == "Up to date" }
        XCTAssertTrue(first)
        try await Task.sleep(for: .milliseconds(1200))
        await model.refresh { SyncResult(state: .offline, pendingCount: 0) }
        let replaced = await wait { self.feedback(in: host).first?.accessibilityLabel == "Needs a connection" }
        XCTAssertTrue(replaced)
        let appearedAt = ContinuousClock.now
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(feedback(in: host).first?.accessibilityLabel, "Needs a connection")
        try await Task.sleep(until: appearedAt + .milliseconds(2100), clock: .continuous)
        let dismissed = await wait { self.feedback(in: host).isEmpty }
        XCTAssertTrue(dismissed)
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

        var capsules: [NSObject] = []
        let appeared = await wait {
            host.window.layoutIfNeeded()
            capsules = self.feedback(in: host)
            return capsules.count == 1 && capsules.first?.accessibilityFrame.isEmpty == false
        }
        XCTAssertTrue(appeared, "Completed native refresh did not present feedback: \(context)")
        let appearedAt = ContinuousClock.now
        XCTAssertEqual(capsules.count, 1, context)
        let capsule = try XCTUnwrap(capsules.first, context)
        XCTAssertEqual(capsule.accessibilityLabel, "Up to date", context)
        XCTAssertFalse(capsule.accessibilityFrame.isEmpty, context)
        XCTAssertEqual(calls, 1, context)
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(
            feedback(in: host).first?.accessibilityLabel, "Up to date", "Feedback disappeared early: \(context)")
        let finished = await wait { !control.isRefreshing }
        XCTAssertTrue(finished, "Native refresh did not finish: \(context)")
        try await Task.sleep(until: appearedAt + .milliseconds(2100), clock: .continuous)
        let dismissed = await wait { self.feedback(in: host).isEmpty }
        XCTAssertTrue(dismissed, "Feedback must dismiss after two seconds: \(context)")
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
