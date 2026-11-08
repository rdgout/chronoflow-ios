import AppCore
import Foundation
import LocalStore
import Observation
import PlanCore
import Sync

@Observable public final class TripPageModel {
    public let tripID: String
    public let plan: TripPlanModel
    public var online = true
    public var syncCompleted = false
    public var awaitingSync: Bool
    public private(set) var fetch: TripPageFetch = .idle
    public private(set) var anchor = TripPageAnchor()
    public var timeline = true
    @ObservationIgnored private let retention: PlanRetention
    @ObservationIgnored private var lease: PlanLease?
    @ObservationIgnored private let fetchDetail: @Sendable (String) async throws -> Void
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var opened = false
    @ObservationIgnored private let requestedDay: String?
    @ObservationIgnored private let blockID: String?
    @ObservationIgnored private let keptDay: String?

    public init(
        tripID: String, repository: TripRepository, retention: PlanRetention,
        dayID: String? = nil, blockID: String? = nil, keptDay: String? = nil, awaitingSync: Bool = false,
        clock: any PlanClock = SystemPlanClock(), now: Date = Date(),
        fetchDetail: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) {
        self.tripID = tripID
        self.retention = retention
        self.requestedDay = dayID
        self.blockID = blockID
        self.keptDay = keptDay
        self.awaitingSync = awaitingSync
        self.fetchDetail = fetchDetail
        plan = TripPlanModel(tripID: tripID, repository: repository, clock: clock, now: now)
    }

    public var state: TripPageState {
        TripPageState.resolve(
            keepOffline: plan.tripRecord?.keepOffline ?? true,
            stored: plan.detail != nil, noPlan: plan.detail?.plan.status == .noPlan, online: online,
            fetch: fetch, missingAfterSync: plan.hasLoaded && plan.tripRecord == nil && syncCompleted,
            tombstoned: plan.tripRecord?.deletedAt != nil || plan.tripRecord?.deletedLocally == true,
            awaitingSync: awaitingSync)
    }

    public func start() {
        guard lease == nil else { return }
        lease = retention.hold(tripID: tripID)
        plan.start()
        retry()
    }

    public func retry() {
        guard fetchTask == nil else { return }
        fetch = .loading
        let request = fetchDetail
        let id = tripID
        fetchTask = Task { [weak self] in
            do {
                try await request(id)
                guard !Task.isCancelled else { return }
                self?.fetch = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                self?.fetch = (error as? DataFailure)?.status == 404 ? .notFound : .failed
            }
            self?.fetchTask = nil
        }
    }

    public func acceptPreparedPlan() {
        guard let detail = plan.detail, plan.prepared != nil else { return }
        if !opened {
            let day = openingDay(
                detail.plan.days, blocks: detail.plan.blocks, requestedDay: requestedDay,
                blockID: blockID, keptDay: keptDay, now: plan.now)
            anchor = TripPageAnchor(dayID: day?.id, labelDate: day?.labelDate)
            opened = true
        } else {
            anchor = replacementAnchor(anchor, days: detail.plan.days)
        }
        awaitingSync = false
    }

    public func select(dayID: String, offset: Double = 0) {
        guard let day = plan.detail?.plan.days.first(where: { $0.id == dayID }) else { return }
        anchor = TripPageAnchor(dayID: day.id, labelDate: day.labelDate, offset: offset)
    }

    public func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        lease?.release()
        lease = nil
        plan.stop()
    }

    deinit {
        fetchTask?.cancel()
        lease?.release()
    }
}
