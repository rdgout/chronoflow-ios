import AppCore
import Foundation
import LocalStore

public enum MemberWizardStep: String, Codable, Sendable { case whereTo, outbound }

public struct WizardAirportSheet: Codable, Sendable, Equatable, Identifiable {
    public enum Side: String, Codable, Sendable { case from, to, home, stop }
    public var index: Int
    public var side: Side
    public var id: String { "\(index)-\(side.rawValue)" }
    public init(index: Int, side: Side) {
        self.index = index
        self.side = side
    }
}

public struct MemberWizardState: Codable, Sendable, Equatable {
    public var instance = UUID().uuidString
    public var revision = 0
    public var step = MemberWizardStep.whereTo
    public var entered = false
    public var fromLastTrip = false
    public var firstTrip = true
    public var sleepNeeded = true
    public var homeChanged = false
    public var profile = JSONObject()
    public var airports: [String: ApiAirportSuggestion] = [:]
    public var sheet: WizardAirportSheet?
    public var savedTripId: String?
    public init() {}
}

public struct MemberWizardDraft: Sendable, Equatable {
    public var form: WizardForm
    public var state: MemberWizardState
    public var airports: [String: ApiAirportSuggestion] {
        get { state.airports }
        set { state.airports = newValue }
    }
    public var fieldErrors: [String: FieldMessage]
    public init(
        form: WizardForm = WizardForm(), state: MemberWizardState = MemberWizardState(),
        airports: [String: ApiAirportSuggestion] = [:], fieldErrors: [String: FieldMessage] = [:]
    ) {
        self.form = form
        self.state = state
        self.fieldErrors = fieldErrors
        self.airports = airports
    }
}

public actor MemberWizardStore {
    private let drafts: DraftRepository
    private let trips: TripRepository
    private let settings: SettingsRepository
    private let permit: SessionMutationPermit?
    private let now: @Sendable () -> Date

    public init(
        database: AccountDatabase, permit: SessionMutationPermit? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        drafts = DraftRepository(database: database)
        trips = TripRepository(database: database)
        settings = SettingsRepository(database: database)
        self.permit = permit
        self.now = now
    }

    public func recover() async throws -> MemberWizardDraft? {
        guard let record = try await drafts.recovery(now: now(), permit: permit) else { return nil }
        do {
            let state = try record.wizardState!.decode(MemberWizardState.self)
            if state.savedTripId != nil {
                try await discard(instance: state.instance)
                return nil
            }
            let form = try record.form.decode(WizardForm.self)
            guard !form.legs.isEmpty, form.legs.count <= WizardForm.maxFlights, form.stays.count == form.legs.count,
                (1...form.legs.count).contains(form.returnBoundary)
            else { throw DataFailure.server(status: nil) }
            return MemberWizardDraft(
                form: form, state: state,
                airports: state.airports,
                fieldErrors: try record.fieldErrors?.decode([String: FieldMessage].self) ?? [:])
        } catch is CancellationError { throw CancellationError() } catch {
            try await drafts.remove(id: record.id, permit: permit)
            return nil
        }
    }

    public func start() async throws -> MemberWizardDraft {
        if let previous = try await recover() { return previous }
        let latest = try await trips.trips().reversed().first { $0.deletedAt == nil && !$0.deletedLocally }
        var draft = MemberWizardDraft()
        draft.state.firstTrip = latest == nil
        if let latest, let card = try? latest.card.decode(TripCardView.self) {
            draft.form.legs[0].fromIata = card.from.iata
            draft.form.legs[0].fromCity = card.from.city
            draft.airports[card.from.iata] = ApiAirportSuggestion(
                iata: card.from.iata, name: card.from.city ?? card.from.iata, city: card.from.city, country: "",
                timezone: card.from.zone)
            draft.state.fromLastTrip = true
            draft.state.firstTrip = false
        }
        let sleep = try await settings.settings().first { $0.section == "sleepAnswered" }
        draft.state.sleepNeeded = (try? sleep?.value.decode(Bool.self)) != true
        try await drafts.createRecovery(record(draft), permit: permit)
        return draft
    }

    public func persist(_ draft: MemberWizardDraft) async throws {
        if draft.state.savedTripId != nil {
            try await discard(instance: draft.state.instance)
            return
        }
        try await drafts.updateRecovery(
            record(draft), instance: draft.state.instance, revision: draft.state.revision, permit: permit)
    }

    public func discard(instance: String) async throws {
        try await drafts.deleteRecovery(instance: instance, permit: permit)
    }
    public func didSave(instance: String) async throws { try await discard(instance: instance) }

    private func record(_ draft: MemberWizardDraft) throws -> DraftRecord {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return DraftRecord(
            id: "member-wizard", form: try .encoding(draft.form),
            dirty: draft.state.entered,
            token: draft.form.identity?.token, inputRevision: draft.form.identity?.inputRevision ?? 0,
            reviewRevision: draft.form.identity?.reviewRevision, furthestStep: draft.state.step.rawValue,
            wizardState: try .encoding(draft.state), fieldErrors: try .encoding(draft.fieldErrors),
            updatedAt: formatter.string(from: now()))
    }
}
