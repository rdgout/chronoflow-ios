import AppCore
import DataAccess
import DesignSystem
import LocalStore
import PlanCore
import PlanUI
import SwiftUI
import Sync
import XCTest

@MainActor final class TripPageSnapshotTests: XCTestCase {
    func testStates() async throws {
        try await AuthTestHost.registerFonts()
        for fixture in try AuthDeviceFixture.authSnapshotProfiles() {
            for (style, language, category) in fixture.authSnapshotVariants {
                for state in TripPageState.allCases {
                    let context = try await TripSnapshotContext(state: state, language: language)
                    let host = try AuthTestHost(
                        NavigationStack { TripPageView(model: context.model) }, size: fixture.size,
                        insets: fixture.insets, style: style, language: language, category: category,
                        scale: fixture.scale)
                    try await context.wait()
                    try await host.settle()
                    let name =
                        "\(fixture.snapshotName)-\(style == .dark ? "dark" : "light")-\(language)-\(category.rawValue)-\(state.rawValue)"
                    let reference = URL(filePath: #filePath).deletingLastPathComponent().appending(
                        path: "__Snapshots__/TripPage/\(name).png")
                    if let failure = try SnapshotReference.verify(
                        png: XCTUnwrap(host.image().pngData()), reference: reference, record: false)
                    {
                        XCTFail(failure)
                    }
                    host.close()
                    try await context.close()
                }
            }
        }
    }

    func testListAndEnd() async throws {
        try await AuthTestHost.registerFonts()
        for fixture in try AuthDeviceFixture.authSnapshotProfiles() {
            for (style, language, category) in fixture.authSnapshotVariants {
                let context = try await TripSnapshotContext(state: .ready, language: language)
                context.model.start()
                try await context.wait()
                let prepared = try XCTUnwrap(context.model.plan.prepared)
                let last = try XCTUnwrap(prepared.days.last)
                context.model.timeline = false
                context.model.acceptPreparedPlan()
                context.model.select(dayID: last.id)
                let view = NavigationStack { TripPageView(model: context.model) }
                let host = try AuthTestHost(
                    view, size: fixture.size, insets: fixture.insets, style: style, language: language,
                    category: category, scale: fixture.scale)
                try await host.settle()
                let reference = URL(filePath: #filePath).deletingLastPathComponent().appending(
                    path:
                        "__Snapshots__/TripPage/\(fixture.snapshotName)-\(style.rawValue)-\(language)-\(category.rawValue)-list-end.png"
                )
                if let failure = try SnapshotReference.verify(
                    png: XCTUnwrap(host.image().pngData()), reference: reference, record: false)
                {
                    XCTFail(failure)
                }
                host.close()
                try await context.close()
            }
        }
    }
}

@MainActor private final class TripSnapshotContext {
    let database: AccountDatabase
    let model: TripPageModel
    let root: URL
    private let state: TripPageState

    init(state: TripPageState, language: String) async throws {
        self.state = state
        root = FileManager.default.temporaryDirectory.appending(path: "trip-snapshot-\(UUID().uuidString)")
        database = AccountDatabase(applicationSupport: root, namespace: .mock)
        let seed = try await Task.detached {
            try MockAppSeed.make(now: Date(timeIntervalSince1970: 1_794_100_000), walkthroughSeen: true)
        }.value
        let account = try XCTUnwrap(seed.accounts[MockScenarioValues.demoID])
        let item = try XCTUnwrap(account.trips.first)
        var detail = try XCTUnwrap(account.details[item.card.id])
        if state == .noPlan { detail.plan.status = .noPlan }
        try await database.open(accountID: account.snapshot.id)
        let repository = TripRepository(database: database)
        let keep = state == .loading || state == .ready || state == .noPlan
        let record = try TripRecord(
            id: item.card.id, card: .encoding(item.card), currentInputHash: item.planInputHash, keepOffline: keep,
            departureUtc: item.card.departureUtc)
        try await repository.upsert(record)
        if state == .ready || state == .noPlan {
            try await repository.store(
                plan: PlanVersionRecord(
                    tripId: item.card.id, inputHash: detail.plan.meta.inputHash,
                    detail: .encoding(detail), receivedAt: detail.trip.departureUtc, detailVersion: detail.detailVersion
                ), checks: [])
        }
        model = TripPageModel(
            tripID: item.card.id, repository: repository, retention: PlanRetention(), clock: FrozenTripClock(),
            now: planDate(detail.plan.days[1].startUtc),
            fetchDetail: { _ in
                if state == .notFound { throw DataFailure.server(status: 404) }
                if state == .server { throw DataFailure.server(status: 500) }
            })
        model.online = state != .remoteOffline
        model.plan.language = language == "nl" ? .nl : .en
    }
    func wait() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while model.state != state || ((state == .ready || state == .noPlan) && model.plan.prepared == nil) {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out preparing \(state)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    func close() async throws {
        model.stop()
        try await database.close()
        try FileManager.default.removeItem(at: root)
    }
}
nonisolated private struct FrozenTripClock: PlanClock {
    func values() async -> AsyncStream<Date> { AsyncStream { $0.finish() } }
}
