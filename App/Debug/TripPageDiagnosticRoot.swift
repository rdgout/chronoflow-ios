#if DEBUG || CHRONOFLOW_TIMELINE_PERF
    import AppCore
    import DataAccess
    import Foundation
    import LocalStore
    import OSLog
    import Observation
    import PlanUI
    import SwiftUI
    import Sync
    import UIKit

    struct TripPageDiagnosticRoot: View {
        let requestedTrip: String
        @State private var model: TripPageModel?
        @State private var failure: String?
        @State private var database: AccountDatabase?
        @State private var probe = TimelineFirstFrameProbe()
        var body: some View {
            NavigationStack {
                if let model {
                    diagnosticPage(model)
                } else if let failure {
                    Text(verbatim: failure).accessibilityIdentifier("trip.diagnostic.failure")
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier(
                probe.finished ? "trip.timeline.presented" : "trip.timeline.opening"
            )
            .task {
                do {
                    let fixture = try await Task.detached { try MockTimelineFixtures.fixture(named: requestedTrip) }
                        .value
                    let id = fixture.card.id
                    let detail = fixture.detail
                    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                        "Timeline-\(UUID().uuidString)")
                    let db = AccountDatabase(applicationSupport: root, namespace: .mock)
                    try await db.open(accountID: "0199a3c0-0000-7000-8000-000000000000")
                    let repo = TripRepository(database: db)
                    let records = try await Task.detached {
                        let trip = try TripRecord(
                            id: id, card: .encoding(fixture.card), currentInputHash: detail.plan.meta.inputHash,
                            keepOffline: true, departureUtc: fixture.card.departureUtc)
                        let plan = try PlanVersionRecord(
                            tripId: id, inputHash: detail.plan.meta.inputHash, detail: .encoding(detail),
                            receivedAt: detail.trip.departureUtc, detailVersion: detail.detailVersion)
                        return (trip, plan)
                    }.value
                    try await repo.upsert(records.0)
                    try await repo.store(plan: records.1, checks: [])
                    database = db
                    probe.begin()
                    model = TripPageModel(
                        tripID: id, repository: repo, retention: PlanRetention(),
                        dayID: detail.plan.days.first?.id)
                } catch { failure = String(describing: error) }
            }
        }
        private func diagnosticPage(_ model: TripPageModel) -> TripPageView {
            var page = TripPageView(model: model, refresh: { nil })
            page.onFirstTimelineFrame = { probe.rendered() }
            return page
        }
        static var requestedTrip: String? {
            #if DEBUG
                let args = UITestRuntime.arguments
            #else
                let args = ProcessInfo.processInfo.arguments
            #endif
            guard let index = args.firstIndex(of: "-cf.trip-page"), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
    }

    @Observable @MainActor private final class TimelineFirstFrameProbe: NSObject {
        private let signposter = OSSignposter(subsystem: "net.chronoflow.app.native", category: "Timeline")
        private var interval: OSSignpostIntervalState?
        private var displayLink: CADisplayLink?
        private var sawFrame = false
        private(set) var finished = false
        func begin() {
            interval = signposter.beginInterval("time-to-first-timeline-frame", id: signposter.makeSignpostID())
        }
        func rendered() {
            guard displayLink == nil, !finished else { return }
            let link = CADisplayLink(target: self, selector: #selector(frame))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }
        @objc private func frame() {
            let overlayVisible = UIApplication.shared.connectedScenes.compactMap { $0.delegate as? SceneDelegate }
                .contains { $0.overlayWindow != nil }
            guard !overlayVisible else { return }
            guard sawFrame else {
                sawFrame = true
                return
            }
            if let interval { signposter.endInterval("time-to-first-timeline-frame", interval) }
            interval = nil
            finished = true
            displayLink?.invalidate()
            displayLink = nil
        }
    }
#endif
