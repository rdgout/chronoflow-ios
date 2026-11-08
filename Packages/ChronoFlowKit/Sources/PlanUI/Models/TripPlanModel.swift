import AppCore
import Foundation
import LocalStore
import Observation
import PlanCore

@Observable public final class TripPlanModel {
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
    @ObservationIgnored private var layoutTask: Task<Void, Never>?
    @ObservationIgnored private var layoutRevision = 0
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public init(
        tripID: String, repository: TripRepository, clock: any PlanClock = SystemPlanClock(),
        decoder: PlanDecoder = PlanDecoder(), now: Date = Date()
    ) {
        self.tripID = tripID
        self.repository = repository
        self.clock = clock
        self.decoder = decoder
        self.now = now
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
                        guard let trip = snapshot.trip, trip.deletedAt == nil, !trip.deletedLocally,
                            let plan = snapshot.plan
                        else {
                            await decoder.evict(tripID: tripID)
                            guard !Task.isCancelled else { break }
                            self?.layoutTask?.cancel()
                            self?.layoutRevision += 1
                            self?.detail = nil
                            self?.error = nil
                            self?.layouts = [:]
                            continue
                        }
                        do {
                            let value = try await decoder.detail(plan)
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
        layoutTask = Task { [weak self] in
            let layouts = await decoder.layouts(detail, hidden: hidden)
            guard !Task.isCancelled, self?.layoutRevision == revision else { return }
            self?.layouts = layouts
        }
    }

    deinit {
        for task in tasks { task.cancel() }
        layoutTask?.cancel()
    }
}
