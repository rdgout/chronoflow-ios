import AppCore
import Foundation
import LocalStore
import Reminders

public enum WizardMode: String, Codable, Sendable { case member, guest }

public enum MemberWizardStep: String, Codable, Sendable {
    case whereTo, outbound, returnChoice, returnRoute, returnFlight, sleep, checking, question, excluded, continuation,
        fineTune, ready, calculating
}

public struct WizardAirportSheet: Codable, Sendable, Equatable, Identifiable {
    public enum Side: String, Codable, Sendable { case from, to, home, stop }
    public var index: Int
    public var side: Side
    public var replacingStop: Bool?
    public var id: String { "\(index)-\(side.rawValue)-\(replacingStop == true)" }
    public init(index: Int, side: Side, replacingStop: Bool = false) {
        self.index = index
        self.side = side
        self.replacingStop = replacingStop ? true : nil
    }
}

public struct MemberWizardState: Codable, Sendable, Equatable {
    private var storedMode: WizardMode? = .member
    public var mode: WizardMode {
        get { storedMode ?? .member }
        set { storedMode = newValue }
    }
    enum CodingKeys: String, CodingKey {
        case storedMode = "mode"
        case instance, revision, step, entered, fromLastTrip, firstTrip, sleepNeeded, homeChanged
        case returnRouteConfirmed, profile, airports, sheet, lastInputStep, progressFloor, review, questions
        case questionIndex, checkingAnswers, sleepCompleted, savedProfile, savedTripId, checkedInput, reviewedAt
        case revisit, returnToReady, promptSheetID, saveFailure, updated, signingIn
        case edit, originalForm, originalInput, copiedRoute, snapshotStayEnd, sourceChange
    }

    public var instance = UUID().uuidString
    public var revision = 0
    public var step = MemberWizardStep.whereTo
    public var entered = false
    public var fromLastTrip = false
    public var firstTrip = true
    public var sleepNeeded = true
    public var homeChanged = false
    public var returnRouteConfirmed: Bool?
    public var profile = JSONObject()
    public var airports: [String: ApiAirportSuggestion] = [:]
    public var sheet: WizardAirportSheet?
    public var lastInputStep: MemberWizardStep?
    public var progressFloor: Double?
    public var review: ApiTripReview?
    public var questions: [ApiReviewPrompt]?
    public var questionIndex: Int?
    public var checkingAnswers: Bool?
    public var sleepCompleted: Bool?
    public var savedProfile: JSONObject?
    public var savedTripId: String?
    public var checkedInput: Data?
    public var reviewedAt: Date?
    public var revisit: Data?
    public var returnToReady: Bool?
    public var promptSheetID: String?
    public var saveFailure: WizardSaveFailure?
    public var updated: Bool?
    public var signingIn: Bool?
    public var edit: TripEditContext?
    public var originalForm: WizardForm?
    public var originalInput: Data?
    public var copiedRoute: String?
    public var snapshotStayEnd: ApiStayEnd?
    public var sourceChange: WizardPresentation.SourceChange?
    public init() {}

    mutating func discardRetiredValues() {
        profile = ProfilePreferences.request(profile)
        savedProfile = savedProfile.map(ProfilePreferences.bodyClock)
        questions = questions.map(ProfilePreferences.reviewPrompts)
        if var value = review {
            value.prompts = ProfilePreferences.reviewPrompts(value.prompts)
            review = value
        }
    }
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

public protocol WizardDraftStore: Sendable {
    func persist(_ draft: MemberWizardDraft) async throws
    func discard(instance: String) async throws
    func didSave(instance: String, firstTrip: Bool) async throws
}

public actor MemberWizardStore: WizardDraftStore {
    private let drafts: DraftRepository
    private let trips: TripRepository
    private let settings: SettingsRepository
    private let remindersOffer: FirstTripRemindersOffer
    private let permit: SessionMutationPermit?
    private let now: @Sendable () -> Date

    public init(
        database: AccountDatabase, permit: SessionMutationPermit? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        drafts = DraftRepository(database: database)
        trips = TripRepository(database: database)
        settings = SettingsRepository(database: database)
        remindersOffer = FirstTripRemindersOffer(database: database, permit: permit)
        self.permit = permit
        self.now = now
    }

    public func recover() async throws -> MemberWizardDraft? {
        guard let record = try await drafts.recovery(now: now(), permit: permit) else { return nil }
        do {
            var state = try record.wizardState!.decode(MemberWizardState.self)
            state.discardRetiredValues()
            let form = try record.form.decode(WizardForm.self)
            guard !form.legs.isEmpty, form.legs.count <= WizardForm.maxFlights, form.stays.count == form.legs.count,
                (1...form.legs.count).contains(form.returnBoundary)
            else { throw DataFailure.server(status: nil) }
            if state.step == .continuation {
                state.step = state.review?.prompts.contains(where: { !$0.blocking }) == true ? .fineTune : .ready
            }
            if state.step == .returnFlight, state.returnRouteConfirmed != true { state.step = .returnRoute }
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
        let draft = try await initialDraft()
        try await drafts.createRecovery(record(draft), permit: permit)
        return draft
    }

    public func start(seed: MemberWizardDraft) async throws -> MemberWizardDraft {
        var draft = try await initialDraft()
        draft.form = seed.form
        draft.form.identity = nil
        draft.form.override = WizardSleepOverride()
        draft.airports = seed.airports
        draft.state.entered = true
        draft.state.fromLastTrip = false
        draft.state.step = .checking
        draft.state.returnToReady = true
        draft.state.profile = JSONObject()
        try await drafts.replaceRecovery(record(draft), permit: permit)
        return draft
    }

    public func startTrip(id: String, action: TripWizardAction, source: any DataSource) async throws
        -> MemberWizardDraft
    {
        let snapshot = try await source.tripInput(id: id)
        try Task.checkCancellation()
        var draft = try await initialDraft()
        try draft.loadTrip(snapshot, id: id, action: action)
        try await drafts.replaceRecovery(record(draft), permit: permit)
        return draft
    }

    private func initialDraft() async throws -> MemberWizardDraft {
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
        let values = try await settings.settings()
        draft.state.savedProfile = try values.first { $0.section == "bodyClock" }?.value.decode(JSONObject.self)
        let sleep = values.first { $0.section == "sleepAnswered" }
        draft.state.sleepNeeded = (try? sleep?.value.decode(Bool.self)) != true
        if draft.state.sleepNeeded, let body = draft.state.savedProfile {
            for (field, key) in [
                ("habitual_bed", "habitualBed"), ("habitual_wake", "habitualWake"), ("chronotype", "chronotype"),
            ] {
                if let value = body[key], value != .null { draft.state.profile[field] = value }
            }
        }
        return draft
    }

    public func persist(_ draft: MemberWizardDraft) async throws {
        try await drafts.updateRecovery(
            record(draft), instance: draft.state.instance, revision: draft.state.revision, permit: permit)
    }

    public func discard(instance: String) async throws {
        try await drafts.deleteRecovery(instance: instance, permit: permit)
    }
    public func didSave(instance: String, firstTrip: Bool) async throws {
        try await remindersOffer.queue(firstTrip: firstTrip)
        try await discard(instance: instance)
    }

    private func record(_ draft: MemberWizardDraft) throws -> DraftRecord {
        var state = draft.state
        state.discardRetiredValues()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return DraftRecord(
            id: "member-wizard", tripId: state.edit?.tripID, form: try .encoding(draft.form),
            baseForm: try state.originalForm.map(JSONDocument.encoding), dirty: draft.hasChanges,
            token: draft.form.identity?.token, inputRevision: draft.form.identity?.inputRevision ?? 0,
            reviewRevision: draft.form.identity?.reviewRevision, wizardSourceRevision: state.edit?.sourceRevision,
            furthestStep: draft.state.step.rawValue,
            wizardState: try .encoding(state), fieldErrors: try .encoding(draft.fieldErrors),
            updatedAt: formatter.string(from: now()))
    }
}
