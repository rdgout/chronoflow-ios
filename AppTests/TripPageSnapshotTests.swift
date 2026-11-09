import AppCore
import DataAccess
import DesignSystem
import LocalStore
import PlanCore
import PlanUI
import SwiftUI
import Sync
import UIKit
import XCTest

nonisolated final class TripPageSnapshotTests: XCTestCase {
    @MainActor func testStates() async throws {
        try await AuthTestHost.registerFonts()
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        for fixture in try AuthDeviceFixture.authSnapshotProfiles() {
            for (style, language, category) in fixture.authSnapshotVariants {
                for state in TripPageState.allCases {
                    let name =
                        "\(fixture.snapshotName)-\(style == .dark ? "dark" : "light")-\(language)-\(category.rawValue)-\(state.rawValue)"
                    func capture() async throws -> Data {
                        try await captureTripPage(
                            state: state, fixture: fixture, style: style, language: language, category: category,
                            formatter: formatter)
                    }
                    let png = try await capture()
                    let repeated = try await capture()
                    guard try SnapshotRaster(png: png) == SnapshotRaster(png: repeated) else {
                        throw TripSnapshotFailure.freshRootsDiffer(name)
                    }
                    let reference = URL(filePath: #filePath).deletingLastPathComponent().appending(
                        path: "__Snapshots__/TripPage/\(name).png")
                    try verifyTripSnapshot(png: png, reference: reference)
                }
            }
        }
    }

    @MainActor func testEndCardStates() async throws {
        try await AuthTestHost.registerFonts()
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        for fixture in try AuthDeviceFixture.authSnapshotProfiles() {
            for (style, language, category) in fixture.authSnapshotVariants {
                for noText in [false, true] {
                    let context = try await TripSnapshotContext(state: .ready, language: language)
                    try await context.wait()
                    var detail = try XCTUnwrap(context.model.plan.detail)
                    if noText {
                        detail.plan.summary = nil
                        for index in detail.plan.days.indices {
                            detail.plan.days[index].notes.removeAll { $0.role == .end }
                        }
                    }
                    let prepared = preparePlan(
                        detail, layouts: context.model.plan.layouts, formatter: formatter,
                        language: language == "nl" ? .nl : .en)
                    let view = ScrollView {
                        EndOfPlanCard(plan: prepared, copy: PageCopy(language: language == "nl" ? .nl : .en)).padding(
                            PlanMetrics.gutter)
                    }
                    let host = try AuthTestHost(
                        view, size: fixture.size, insets: fixture.insets, style: style, language: language,
                        category: category, scale: fixture.scale)
                    try await host.settle()
                    let name =
                        "\(fixture.snapshotName)-\(style.rawValue)-\(language)-\(category.rawValue)-end-\(noText ? "no-text" : "text")"
                    let reference = URL(filePath: #filePath).deletingLastPathComponent().appending(
                        path: "__Snapshots__/TripPage/\(name).png")
                    try verifyTripSnapshot(png: XCTUnwrap(host.image().pngData()), reference: reference)
                    host.close()
                    try await context.close()
                }
            }
        }
    }

    @MainActor func testListAndEnd() async throws {
        try await AuthTestHost.registerFonts()
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        for fixture in try AuthDeviceFixture.authSnapshotProfiles() {
            for (style, language, category) in fixture.authSnapshotVariants {
                let context = try await TripSnapshotContext(state: .ready, language: language)
                try await context.wait()
                let prepared = try XCTUnwrap(context.model.plan.prepared)
                let last = try XCTUnwrap(prepared.days.last)
                context.model.timeline = false
                context.model.acceptPreparedPlan()
                context.model.select(dayID: last.id)
                let view = NavigationStack {
                    TripPageView(model: context.model, formatter: formatter, refresh: { nil })
                }
                .transaction {
                    $0.disablesAnimations = true
                    $0.animation = nil
                }
                let host = try AuthTestHost(
                    view, size: fixture.size, insets: fixture.insets, style: style, language: language,
                    category: category, scale: fixture.scale)
                let chrome = TripSnapshotChrome(style: style)
                host.prepareCapture = chrome.prepare
                try await host.settle()
                let reference = URL(filePath: #filePath).deletingLastPathComponent().appending(
                    path:
                        "__Snapshots__/TripPage/\(fixture.snapshotName)-\(style.rawValue)-\(language)-\(category.rawValue)-list-end.png"
                )
                try verifyTripSnapshot(png: XCTUnwrap(host.image().pngData()), reference: reference)
                host.close()
                try await context.close()
            }
        }
    }
}

@MainActor private func verifyTripSnapshot(png: Data, reference: URL) throws {
    let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
    let failure = try SnapshotReference.verify(png: png, reference: reference, record: record)
    if record {
        XCTAssertTrue(failure?.hasPrefix("Record mode is on.") == true)
    } else if let failure {
        XCTFail(failure)
    }
}

@MainActor private func captureTripPage(
    state: TripPageState, fixture: AuthDeviceFixture, style: UIUserInterfaceStyle, language: String,
    category: UIContentSizeCategory, formatter: CopyLineFormatter
) async throws -> Data {
    let context = try await TripSnapshotContext(state: state, language: language)
    do {
        try await context.wait()
        var page = TripPageView(model: context.model, formatter: formatter, refresh: { nil })
        page.onFirstTimelineFrame = { context.timelineReady = true }
        let host = try AuthTestHost(
            NavigationStack { page }.transaction {
                $0.disablesAnimations = true
                $0.animation = nil
            },
            size: fixture.size, insets: fixture.insets, style: style, language: language, category: category,
            scale: fixture.scale)
        defer { host.close() }
        let chrome = TripSnapshotChrome(style: style)
        host.prepareCapture = chrome.prepare
        try await context.waitForTimeline(in: host)
        try await host.settle()
        let png = try XCTUnwrap(host.image().pngData())
        try await context.close()
        return png
    } catch {
        try? await context.close()
        throw error
    }
}

private enum TripSnapshotFailure: Error {
    case timedOut(TripPageState, TripPageState)
    case timelineNotReady
    case freshRootsDiffer(String)
}

@MainActor private final class TripSnapshotChrome {
    private let background: UIColor
    private var bars: Set<ObjectIdentifier> = []

    init(style: UIUserInterfaceStyle) {
        background = UIColor(cgColor: ColorToken.background.components(for: style == .dark ? .dark : .light).cgColor)
    }

    func prepare(_ view: UIView) {
        // CPU layer capture cannot reproduce the render server's live glass and scroll-edge textures.
        if let bar = view as? UINavigationBar {
            if bars.insert(ObjectIdentifier(bar)).inserted {
                let appearance = bar.standardAppearance.copy() as! UINavigationBarAppearance
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = background
                bar.standardAppearance = appearance
                bar.scrollEdgeAppearance = appearance
                bar.compactAppearance = appearance
                bar.compactScrollEdgeAppearance = appearance
            }
            if #available(iOS 26, *) {
                for item in bar.items ?? [] {
                    for button in (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? []) {
                        button.hidesSharedBackground = true
                    }
                }
            }
        }
        if let effect = view as? UIVisualEffectView, effect.effect != nil { effect.effect = nil }
        if #available(iOS 26, *), let scroll = view as? UIScrollView {
            scroll.topEdgeEffect.isHidden = true
            scroll.bottomEdgeEffect.isHidden = true
            scroll.leftEdgeEffect.isHidden = true
            scroll.rightEdgeEffect.isHidden = true
        }
        view.subviews.forEach(prepare)
    }
}

@MainActor final class TripSnapshotContext {
    let database: AccountDatabase
    let model: TripPageModel
    let root: URL
    private let state: TripPageState
    var timelineReady = false

    init(state: TripPageState, language: String) async throws {
        self.state = state
        root = FileManager.default.temporaryDirectory.appending(path: "trip-snapshot-\(UUID().uuidString)")
        database = AccountDatabase(applicationSupport: root, namespace: .mock)
        let seed = try await Task.detached {
            try MockAppSeed.make(now: Date(timeIntervalSince1970: 1_794_100_000), walkthroughSeen: true)
        }.value
        let account = try XCTUnwrap(seed.accounts["0199a3c0-0000-7000-8000-000000000000"])
        let item = try XCTUnwrap(account.trips.first)
        var detail = try XCTUnwrap(account.details[item.card.id])
        if state == .noPlan { detail.plan.status = .noPlan }
        try await database.open(accountID: account.snapshot.id)
        let repository = TripRepository(database: database)
        let keep = state == .loading || state == .ready || state == .noPlan
        let record = try TripRecord(
            id: item.card.id, card: .encoding(item.card), adaptation: item.adaptation.map { try .encoding($0) },
            currentInputHash: item.planInputHash, keepOffline: keep,
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
            tripID: item.card.id, repository: repository, retention: PlanRetention(), path: nil,
            clock: FrozenTripClock(),
            now: planDate(detail.plan.days[1].startUtc),
            fetchDetail: { _ in
                if state == .notFound { throw DataFailure.server(status: 404) }
                if state == .server { throw DataFailure.server(status: 500) }
            })
        model.online = state != .remoteOffline
        model.plan.language = language == "nl" ? .nl : .en
        model.start()
    }
    func wait() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !isReady {
            guard ContinuousClock.now < deadline else {
                throw TripSnapshotFailure.timedOut(state, model.state)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private var isReady: Bool {
        guard model.state == state, model.plan.card != nil, model.plan.adaptation != nil else { return false }
        guard state == .ready || state == .noPlan else { return true }
        return model.plan.prepared != nil
            && model.plan.layouts.values.allSatisfy {
                nowLineOffset($0.day, now: model.plan.now) == nil || model.plan.nowTexts[$0.day.id]?.isEmpty == false
            }
    }
    func waitForTimeline(in host: AuthTestHost) async throws {
        guard state == .ready else { return }
        let deadline = ContinuousClock.now + .seconds(10)
        while !timelineReady {
            _ = try host.image()
            guard ContinuousClock.now < deadline else { throw TripSnapshotFailure.timelineNotReady }
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
