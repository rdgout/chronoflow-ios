import AppCore
import Foundation
import Observation

public protocol MemberWizardGeneration: Sendable {
    func review(instance: String, input: ApiTripReviewInput) async throws -> TripGenerationReviewResult
    func save(_ state: TripGenerationState, didCreate: @escaping @Sendable (String) async throws -> Void) async throws
        -> TripGenerationSaveResult
    func cancelReviews(instance: String) async
    func cancel() async
}

extension MemberWizardGeneration {
    public func save(_ state: TripGenerationState, didCreate: @escaping @Sendable (String) async throws -> Void)
        async throws -> TripGenerationSaveResult
    {
        throw DataFailure.server(status: nil)
    }
}

extension TripGenerationService: MemberWizardGeneration {
    public func review(instance: String, input: ApiTripReviewInput) async throws -> TripGenerationReviewResult {
        try await review(instance: instance, input: input, edit: nil)
    }
}

@MainActor @Observable
public final class MemberWizardModel {
    public internal(set) var draft: MemberWizardDraft
    public internal(set) var closed = false
    public private(set) var persistenceFailed = false
    public let search: AirportSearchService
    public internal(set) var checking = WizardCheckingProgress()
    public internal(set) var retrySeconds = 0
    public internal(set) var choicePending = false
    public internal(set) var reviewing = false
    public internal(set) var createdTripID: String?
    @ObservationIgnored var retryTask: Task<Void, Never>?
    @ObservationIgnored var retryID = UUID()
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var reviewTask: Task<Void, Never>?
    @ObservationIgnored var resumed = false
    #if DEBUG
        public internal(set) var boardAnswerError: String?
        @ObservationIgnored var boardFrozen = false
    #endif
    let generation: (any MemberWizardGeneration)?
    let checkingClock: WizardCheckingClock
    @ObservationIgnored var checkTask: Task<Void, Never>?
    @ObservationIgnored var choiceTask: Task<Void, Never>?
    @ObservationIgnored var checkID = UUID()
    @ObservationIgnored var checkInstance: String?
    let store: any WizardDraftStore
    let now: @Sendable () -> Date
    @ObservationIgnored private var pending: Task<Void, Never>?

    public init(
        draft: MemberWizardDraft, store: any WizardDraftStore, search: AirportSearchService,
        now: @escaping @Sendable () -> Date = { Date() },
        generation: (any MemberWizardGeneration)? = nil, checkingClock: WizardCheckingClock = .continuous
    ) {
        var draft = draft
        draft.state.discardRetiredValues()
        self.draft = draft
        self.store = store
        self.search = search
        self.now = now
        self.generation = generation
        self.checkingClock = checkingClock
        restartRetryCountdown()
    }

    public var whereComplete: Bool {
        draft.form.routeComplete()
    }

    public var returnRouteComplete: Bool { draft.form.routeComplete(home: true) }

    public var outboundComplete: Bool {
        draft.form.legs.prefix(draft.form.returnBoundary).allSatisfy {
            WizardDateTime.date($0.departLocal) != nil && WizardDateTime.date($0.arriveLocal) != nil
        }
    }

    public func go(_ step: MemberWizardStep) {
        guard !closed, !persistenceFailed, draft.state.step != .calculating else { return }
        if reviewing { cancelInlineReview() }
        if draft.state.step == .checking, step != .checking {
            cancelCheck()
            checking = WizardCheckingProgress()
        }
        choiceTask?.cancel()
        choicePending = false
        if [.checking, .question, .excluded, .continuation, .fineTune, .ready, .calculating].contains(step) {
            draft.state.progressFloor = progress
        } else {
            draft.state.progressFloor = nil
        }
        draft.state.step = step
        restartRetryCountdown()
        persist()
    }

    public func openAirport(_ sheet: WizardAirportSheet?) {
        guard !closed else { return }
        draft.state.sheet = sheet
        persist()
    }

    public func chooseAirport(_ airport: ApiAirportSuggestion, sheet: WizardAirportSheet) {
        guard !closed, airportIsAllowed(airport.iata, sheet: sheet) else { return }
        let home = sheet.index >= draft.form.returnBoundary
        draft.airports[airport.iata] = airport
        if sheet.side == .stop {
            if sheet.replacingStop == true {
                draft.form.setRouteAirport(
                    airport, at: sheet.index + 1 - (home ? draft.form.returnBoundary : 0), home: home)
            } else {
                let last = home ? draft.form.legs.count - 1 : draft.form.returnBoundary - 1
                draft.form.insertStop(airport, beforeDestinationOf: last)
            }
        } else {
            let position = sheet.side == .from ? 0 : sheet.index + 1 - (home ? draft.form.returnBoundary : 0)
            draft.form.setRouteAirport(airport, at: position, home: home)
            if sheet.side == .from { draft.state.fromLastTrip = false }
            if home { draft.state.homeChanged = true }
            if sheet.side == .from, draft.form.end.kind == "return_legs", !draft.state.homeChanged {
                let last = draft.form.legs.count - 1
                draft.form.updateLeg(last) {
                    $0.toIata = airport.iata
                    $0.toCity = airport.city
                }
            }
        }
        draft.state.sheet = nil
        changed()
    }

    public func airportIsAllowed(_ iata: String, sheet: WizardAirportSheet) -> Bool {
        guard draft.form.legs.indices.contains(sheet.index) else { return false }
        let home = sheet.index >= draft.form.returnBoundary
        let route = draft.form.route(home: home)
        if sheet.side == .stop, sheet.replacingStop != true {
            return !route.suffix(2).contains { $0.iata == iata }
        }
        let position = sheet.side == .from ? 0 : sheet.index + 1 - (home ? draft.form.returnBoundary : 0)
        guard route.indices.contains(position), !home || position > 0 else { return false }
        if route.count == 2 { return true }
        return ![position - 1, position + 1].contains { neighbor in
            route.indices.contains(neighbor) && route[neighbor].iata == iata
        }
    }

    public func swapAirports() {
        guard !closed, draft.form.returnBoundary == 1, let first = draft.form.legs.first,
            let last = draft.form.legs.prefix(draft.form.returnBoundary).last,
            !first.fromIata.isEmpty, !last.toIata.isEmpty
        else { return }
        draft.form.updateLeg(0) {
            $0.fromIata = last.toIata
            $0.fromCity = last.toCity
        }
        draft.form.updateLeg(draft.form.returnBoundary - 1) {
            $0.toIata = first.fromIata
            $0.toCity = first.fromCity
        }
        if draft.form.end.kind == "return_legs", !draft.state.homeChanged {
            draft.form.updateLeg(draft.form.legs.count - 1) {
                $0.toIata = last.toIata
                $0.toCity = last.toCity
            }
        }
        draft.state.fromLastTrip = false
        changed()
    }

    public func setDateTime(_ value: String, index: Int, arrival: Bool) {
        guard !closed, WizardDateTime.date(value) != nil else { return }
        draft.form.updateLeg(index) { if arrival { $0.arriveLocal = value } else { $0.departLocal = value } }
        changed()
    }

    public func removeStop(at index: Int) {
        guard !closed else { return }
        draft.form.removeStop(at: index)
        changed()
    }

    public func makeDirect(home: Bool = false) {
        guard !closed else { return }
        draft.form.makeDirect(home: home)
        changed()
    }

    public func finishReturnRoute() {
        guard !closed, !persistenceFailed, returnRouteComplete else { return }
        draft.state.returnRouteConfirmed = true
        go(.returnFlight)
    }

    public func finishOutbound() -> Bool {
        guard !closed, !persistenceFailed, outboundComplete else { return false }
        draft.fieldErrors = WizardOutboundRules.errors(
            form: draft.form, airports: draft.airports, now: now(), checkPast: false)
        persist()
        return draft.fieldErrors.isEmpty
    }

    public func flush() async { await pending?.value }

    public func discard() async throws {
        guard !closed, draft.state.step != .calculating else { return }
        closed = true
        restartRetryCountdown()
        cancelInlineReview()
        cancelCheck()
        choiceTask?.cancel()
        await generation?.cancel()
        await flush()
        do { try await store.discard(instance: draft.state.instance) } catch {
            closed = false
            restartRetryCountdown()
            throw error
        }
    }

    func changed() {
        draft.state.entered = true
        draft.fieldErrors = [:]
        persist()
    }

    func persist() {
        draft.state.revision += 1
        let value = draft
        let previous = pending
        pending = Task { [weak self, store] in
            await previous?.value
            do { try await store.persist(value) } catch is CancellationError { return } catch {
                self?.persistenceFailed = true
            }
        }
    }
}
