import AppCore
import Foundation
import LocalStore
import Observation
import PlanCore
import Sync

@Observable public final class TripPageModel {
    public let tripID: String
    public let plan: TripPlanModel
    public var online = true {
        didSet {
            if online && !oldValue && lease != nil {
                if fetchTask != nil { reconnectPending = true } else { retry() }
            }
        }
    }
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
    @ObservationIgnored private let path: (any SyncPathMonitoring)?
    @ObservationIgnored private var pathTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectPending = false
    @ObservationIgnored private var scrollOffset: Double = 0
    @ObservationIgnored private var settingsTask: Task<Void, Never>?
    @ObservationIgnored private let settings: SettingsRepository
    @ObservationIgnored private let requestedDay: String?
    @ObservationIgnored private let blockID: String?
    @ObservationIgnored private let keptDay: String?

    public init(
        tripID: String, repository: TripRepository, retention: PlanRetention,
        dayID: String? = nil, blockID: String? = nil, keptDay: String? = nil, awaitingSync: Bool = false,
        path: (any SyncPathMonitoring)? = TripPagePathMonitor(),
        timeFormat: TimeFormat = .value24, hiddenCategories: [BlockType] = [],
        clock: any PlanClock = SystemPlanClock(), now: Date = Date(), mutationPermit: SessionMutationPermit? = nil,
        fetchDetail: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) {
        self.tripID = tripID
        self.path = path
        settings = SettingsRepository(database: repository.database)
        self.retention = retention
        self.requestedDay = dayID
        self.blockID = blockID
        self.keptDay = keptDay
        self.awaitingSync = awaitingSync
        self.fetchDetail = fetchDetail
        plan = TripPlanModel(
            tripID: tripID, repository: repository, clock: clock, now: now, mutationPermit: mutationPermit)
        plan.timeFormat = timeFormat
        plan.hiddenCategories = hiddenCategories
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
        plan.onTripAvailable = { [weak self] in self?.awaitingSync = false }
        plan.start()
        if let path {
            pathTask = Task { [weak self] in
                for await online in await path.updates() {
                    guard !Task.isCancelled else { break }
                    self?.online = online
                }
            }
        }
        let settings = settings
        settingsTask = Task { [weak self] in
            do {
                for try await rows in try await settings.values() {
                    guard !Task.isCancelled else { return }
                    guard let row = rows.first(where: { $0.section == "preferences" }),
                        let preferences = try? row.value.decode(JSONObject.self)
                    else { continue }
                    if let raw = preferences["timeFormat"]?.string {
                        self?.plan.timeFormat = TimeFormat(rawValue: raw)
                    }
                    if case .array(let values) = preferences["hiddenCategories"] {
                        self?.plan.hiddenCategories = values.compactMap { $0.string.map(BlockType.init(rawValue:)) }
                    }
                }
            } catch {}
        }
        retry()
    }

    public func retry() {
        guard fetchTask == nil else { return }
        guard online else {
            fetch = .offline
            return
        }
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
                switch error as? DataFailure {
                case .offline: self?.fetch = .offline
                case let failure where failure?.status == 404: self?.fetch = .notFound
                default: self?.fetch = .failed
                }
            }
            self?.fetchTask = nil
            if self?.reconnectPending == true {
                self?.reconnectPending = false
                if self?.online == true { self?.retry() }
            }
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
            anchor = replacementAnchor(currentAnchor, days: detail.plan.days)
        }
    }

    public var currentAnchor: TripPageAnchor {
        var value = anchor
        value.offset = scrollOffset
        return value
    }

    public func select(dayID: String, offset: Double = 0) {
        scrollOffset = offset
        guard anchor.dayID != dayID else { return }
        guard let day = plan.detail?.plan.days.first(where: { $0.id == dayID }) else { return }
        anchor = TripPageAnchor(dayID: day.id, labelDate: day.labelDate, offset: offset)
    }

    public func stop() {
        pathTask?.cancel()
        pathTask = nil
        reconnectPending = false
        settingsTask?.cancel()
        settingsTask = nil
        fetchTask?.cancel()
        fetchTask = nil
        lease?.release()
        lease = nil
        plan.stop()
    }

    deinit {
        pathTask?.cancel()
        settingsTask?.cancel()
        fetchTask?.cancel()
        lease?.release()
    }
}
