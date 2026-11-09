import Foundation
import LocalStore
import Observation
import PlanCore

@Observable public final class TripsModel {
    public private(set) var trips: [TripListValue] = []
    public private(set) var hasLoaded = false
    public private(set) var now: Date
    public private(set) var error: (any Error)?
    @ObservationIgnored private let repository: TripRepository
    @ObservationIgnored private let clock: any PlanClock
    @ObservationIgnored private let decoder: PlanDecoder
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public init(
        repository: TripRepository, clock: any PlanClock = SystemPlanClock(), decoder: PlanDecoder = PlanDecoder(),
        now: Date = Date()
    ) {
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
        tasks = [
            Task { [weak self] in
                do {
                    for try await records in try await repository.values() {
                        guard !Task.isCancelled else { break }
                        let result = await decoder.trips(records, now: self?.now ?? Date())
                        guard !Task.isCancelled else { break }
                        self?.trips = result.values
                        self?.hasLoaded = true
                        if let self { self.updateNow(self.now) }
                        self?.error = result.error
                    }
                } catch { if !Task.isCancelled { self?.error = error } }
            },
            Task { [weak self] in
                for await date in await clock.values() {
                    guard !Task.isCancelled else { break }
                    self?.updateNow(date)
                }
            },
        ]
    }

    public func stop() {
        for task in tasks { task.cancel() }
        tasks.removeAll()
    }

    private func updateNow(_ date: Date) {
        now = date
        trips = trips.map { value in
            var value = value
            value.status = tripDisplayStatus(
                value.card, planStartUtc: value.planStartUtc, planEndUtc: value.planEndUtc, now: date)
            return value
        }
    }

    deinit { for task in tasks { task.cancel() } }
}
