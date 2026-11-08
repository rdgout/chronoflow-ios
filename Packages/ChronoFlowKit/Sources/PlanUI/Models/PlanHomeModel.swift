import AppCore
import Foundation
import LocalStore
import Observation
import PlanCore

@Observable public final class PlanHomeModel {
    public let trips: TripsModel
    public private(set) var selected: TripPlanModel?
    public private(set) var details: [String: TripPlanModel] = [:]
    public private(set) var formatter: CopyLineFormatter?
    public private(set) var synced = false
    public private(set) var hidden: [BlockType] = []
    public private(set) var timeFormat: TimeFormat = .value24
    public private(set) var mutationError: (any Error)?
    public private(set) var changingCheck = false
    @ObservationIgnored private let repository: TripRepository
    @ObservationIgnored private let clock: any PlanClock
    @ObservationIgnored private let mutationPermit: SessionMutationPermit?
    @ObservationIgnored private var selectedID: String?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public init(
        repository: TripRepository, clock: any PlanClock = SystemPlanClock(), now: Date = Date(),
        mutationPermit: SessionMutationPermit? = nil
    ) {
        self.repository = repository
        self.clock = clock
        self.mutationPermit = mutationPermit
        trips = TripsModel(repository: repository, clock: clock, now: now)
    }
    public var hero: TripListValue? { selectTodayTrip(trips.trips, now: trips.now) }
    public func start() {
        guard tasks.isEmpty else { return }
        trips.start()
        tasks = [
            Task { [weak self] in self?.formatter = try? await CopyLineFormatter(catalog: CopyCatalog.load()) },
            Task { [weak self, repository] in
                do {
                    for try await account in try await AccountRepository(database: repository.database).values() {
                        guard !Task.isCancelled else { return }
                        self?.synced = account?.syncedAt != nil
                    }
                } catch {}
            },
            Task { [weak self, repository] in
                do {
                    for try await settings in try await SettingsRepository(database: repository.database).values() {
                        guard !Task.isCancelled else { return }
                        let value = try settings.first { $0.section == "preferences" }?.value.decode(JSONObject.self)
                        if case .array(let categories) = value?["hiddenCategories"] {
                            self?.hidden = categories.compactMap { $0.string.map(BlockType.init(rawValue:)) }
                        } else {
                            self?.hidden = []
                        }
                        self?.timeFormat = TimeFormat(rawValue: value?["timeFormat"]?.string ?? "24")
                    }
                } catch {}
            },
        ]
    }
    public func selectHero() {
        let id = hero?.card.id
        guard id != selectedID else { return }
        selectedID = id
        selected = id.map { detail(for: $0) }
    }
    public func detail(for id: String) -> TripPlanModel {
        if let existing = details[id] { return existing }
        let model = TripPlanModel(
            tripID: id, repository: repository, clock: clock, now: trips.now, mutationPermit: mutationPermit)
        details[id] = model
        model.start()
        return model
    }
    public func setCheck(tripID: String, blockID: String, status: CheckStatus?) async {
        guard !tasks.isEmpty, !changingCheck else { return }
        changingCheck = true
        defer { changingCheck = false }
        do {
            try await details[tripID]?.setCheck(blockID: blockID, status: status)
            mutationError = nil
        } catch { mutationError = error }
    }
    public func stop() {
        trips.stop()
        for model in details.values { model.stop() }
        for task in tasks { task.cancel() }
        tasks.removeAll()
        details.removeAll()
        selected = nil
        selectedID = nil
    }
    deinit { for task in tasks { task.cancel() } }
}
