import AppCore
import Foundation
import LocalStore
import Observation
import PlanCore

@Observable public final class TripPlanModel {
    public private(set) var tripRecord: TripRecord?
    public private(set) var card: TripCardView?
    public private(set) var adaptation: AdaptationView?
    public private(set) var hasLoaded = false
    public private(set) var prepared: PreparedPlan?
    public var language: Language = .en { didSet { if language != oldValue { rebuildLayouts() } } }
    public var timeFormat: TimeFormat = .value24 { didSet { if timeFormat != oldValue { rebuildLayouts() } } }
    @ObservationIgnored private var marks: [CheckMark] = []
    @ObservationIgnored private var pendingChecks: [CheckOffChange] = []
    public private(set) var detail: TripDetail?
    public private(set) var layouts: [String: DayLayout] = [:]
    public private(set) var now: Date
    public private(set) var error: (any Error)?
    public var hiddenCategories: [BlockType] = [] { didSet { rebuildLayouts() } }
    public var nowOffsets: [String: Double] {
        layouts.compactMapValues { nowLineOffset($0.day, now: now) }
    }
    @ObservationIgnored private let tripID: String
    @ObservationIgnored private let repository: TripRepository
    @ObservationIgnored private let clock: any PlanClock
    @ObservationIgnored private let decoder: PlanDecoder
    @ObservationIgnored private let mutationPermit: SessionMutationPermit?
    @ObservationIgnored private var layoutTask: Task<Void, Never>?
    @ObservationIgnored private var layoutRevision = 0
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public init(
        tripID: String, repository: TripRepository, clock: any PlanClock = SystemPlanClock(),
        decoder: PlanDecoder = PlanDecoder(), now: Date = Date(), mutationPermit: SessionMutationPermit? = nil
    ) {
        self.tripID = tripID
        self.repository = repository
        self.clock = clock
        self.decoder = decoder
        self.now = now
        self.mutationPermit = mutationPermit
    }

    public func start() {
        guard tasks.isEmpty else { return }
        let repository = repository
        let clock = clock
        let decoder = decoder
        let tripID = tripID
        tasks = [
            Task { [weak self] in
                do {
                    for try await snapshot in try await repository.detailValues(tripID: tripID) {
                        guard !Task.isCancelled else { break }
                        self?.tripRecord = snapshot.trip
                        self?.hasLoaded = true
                        if let trip = snapshot.trip {
                            self?.card = try? await decoder.card(trip)
                            self?.adaptation = try? await decoder.adaptation(trip)
                        }
                        self?.pendingChecks = snapshot.pendingChecks
                        self?.marks = snapshot.checks.map {
                            CheckMark(
                                key: CheckKeyView(
                                    type: BlockType(rawValue: $0.type), localDate: $0.localDate, ordinal: $0.ordinal),
                                status: CheckStatus(rawValue: $0.status), markedAt: $0.markedAt)
                        }
                        guard let trip = snapshot.trip, trip.deletedAt == nil, !trip.deletedLocally,
                            snapshot.plan != nil
                        else {
                            await decoder.evict(tripID: tripID)
                            guard !Task.isCancelled else { break }
                            self?.layoutTask?.cancel()
                            self?.layoutRevision += 1
                            self?.detail = nil
                            self?.error = nil
                            self?.layouts = [:]
                            self?.prepared = nil
                            continue
                        }
                        do {
                            let value = try await decoder.detail(snapshot)
                            guard !Task.isCancelled else { break }
                            self?.detail = value
                            self?.rebuildLayouts()
                            self?.error = nil
                        } catch { if !Task.isCancelled { self?.error = error } }
                    }
                } catch { if !Task.isCancelled { self?.error = error } }
            },
            Task { [weak self] in
                for await date in await clock.values() {
                    guard !Task.isCancelled else { break }
                    self?.now = date
                }
            },
        ]
    }

    public func setCheck(blockID: String, status: CheckStatus?) async throws {
        guard !tasks.isEmpty, let detail, let block = detail.plan.blocks.first(where: { $0.id == blockID }),
            block.actionable, let key = block.checkKey
        else { return }
        try await OutboxRepository(database: repository.database).enqueue(
            .checkOff(
                CheckOffChange(
                    tripID: tripID, planInputHash: detail.plan.meta.inputHash, type: key.type,
                    localDate: key.localDate, ordinal: key.ordinal, status: status)), permit: mutationPermit)
    }

    public func stop() {
        for task in tasks { task.cancel() }
        tasks.removeAll()
        layoutTask?.cancel()
        layoutRevision += 1
    }

    private func rebuildLayouts() {
        layoutTask?.cancel()
        layoutRevision += 1
        let revision = layoutRevision
        guard let detail else {
            layouts = [:]
            return
        }
        let decoder = decoder
        let hidden = hiddenCategories
        let language = language
        let timeFormat = timeFormat
        let marks = marks
        let pendingChecks = pendingChecks
        layoutTask = Task { [weak self] in
            let layouts = await decoder.layouts(detail, hidden: hidden)
            guard !Task.isCancelled, self?.layoutRevision == revision else { return }
            do {
                let prepared = try await decoder.prepare(
                    detail, hidden: hidden, language: language, timeFormat: timeFormat, marks: marks,
                    pendingChecks: pendingChecks)
                guard !Task.isCancelled, self?.layoutRevision == revision else { return }
                self?.layouts = layouts
                self?.prepared = prepared
            } catch { if !Task.isCancelled { self?.error = error } }
        }
    }

    deinit {
        for task in tasks { task.cancel() }
        layoutTask?.cancel()
    }
}
