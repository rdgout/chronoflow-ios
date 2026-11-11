import AppCore
import Foundation
import Observation

public protocol MemberWizardGeneration: Sendable {
    func review(instance: String, input: ApiTripReviewInput) async throws -> TripGenerationReviewResult
    func cancelReviews(instance: String) async
    func cancel() async
}

extension TripGenerationService: MemberWizardGeneration {
    public func review(instance: String, input: ApiTripReviewInput) async throws -> TripGenerationReviewResult {
        try await review(instance: instance, input: input, edit: nil)
    }
}

@MainActor @Observable
public final class MemberWizardModel {
    public internal(set) var draft: MemberWizardDraft
    public private(set) var closed = false
    public private(set) var persistenceFailed = false
    public let search: AirportSearchService
    public internal(set) var checking = WizardCheckingProgress()
    public internal(set) var retrySeconds = 0
    public internal(set) var choicePending = false
    let generation: (any MemberWizardGeneration)?
    let checkingClock: WizardCheckingClock
    @ObservationIgnored var checkTask: Task<Void, Never>?
    @ObservationIgnored var choiceTask: Task<Void, Never>?
    @ObservationIgnored var checkID = UUID()
    @ObservationIgnored var checkInstance: String?
    let store: MemberWizardStore
    let now: @Sendable () -> Date
    @ObservationIgnored private var pending: Task<Void, Never>?

    public init(
        draft: MemberWizardDraft, store: MemberWizardStore, search: AirportSearchService,
        now: @escaping @Sendable () -> Date = { Date() },
        generation: (any MemberWizardGeneration)? = nil, checkingClock: WizardCheckingClock = .continuous
    ) {
        self.draft = draft
        self.store = store
        self.search = search
        self.now = now
        self.generation = generation
        self.checkingClock = checkingClock
    }

    public var whereComplete: Bool {
        guard let first = draft.form.legs.first, let last = draft.form.legs.prefix(draft.form.returnBoundary).last
        else { return false }
        return !first.fromIata.isEmpty && !last.toIata.isEmpty && first.fromIata != last.toIata
    }

    public var outboundComplete: Bool {
        draft.form.legs.prefix(draft.form.returnBoundary).allSatisfy {
            WizardDateTime.date($0.departLocal) != nil && WizardDateTime.date($0.arriveLocal) != nil
        }
    }

    public func go(_ step: MemberWizardStep) {
        guard !closed, !persistenceFailed else { return }
        if draft.state.step == .checking, step != .checking { cancelCheck() }
        choiceTask?.cancel()
        choicePending = false
        if [.checking, .question, .excluded, .continuation].contains(step) {
            draft.state.progressFloor = progress
        } else {
            draft.state.progressFloor = nil
        }
        draft.state.step = step
        persist()
    }

    public func openAirport(_ sheet: WizardAirportSheet?) {
        guard !closed else { return }
        draft.state.sheet = sheet
        persist()
    }

    public func chooseAirport(_ airport: ApiAirportSuggestion, sheet: WizardAirportSheet) {
        guard !closed, draft.form.legs.indices.contains(sheet.index) else { return }
        draft.airports[airport.iata] = airport
        if sheet.side == .stop {
            draft.form.insertStop(airport, beforeDestinationOf: sheet.index)
        } else {
            draft.form.updateLeg(sheet.index) { leg in
                if sheet.side == .from {
                    leg.fromIata = airport.iata
                    leg.fromCity = airport.city
                } else {
                    leg.toIata = airport.iata
                    leg.toCity = airport.city
                }
            }
            if sheet.side == .from { draft.state.fromLastTrip = false }
            if sheet.side == .home { draft.state.homeChanged = true }
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

    public func swapAirports() {
        guard !closed, let first = draft.form.legs.first,
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

    public func finishOutbound() -> Bool {
        guard !closed, !persistenceFailed, outboundComplete else { return false }
        draft.fieldErrors = WizardOutboundRules.errors(
            form: draft.form, airports: draft.airports, now: now(), checkPast: false)
        persist()
        return draft.fieldErrors.isEmpty
    }

    public func flush() async { await pending?.value }

    public func discard() async throws {
        guard !closed else { return }
        closed = true
        cancelCheck()
        choiceTask?.cancel()
        await generation?.cancel()
        await flush()
        do { try await store.discard(instance: draft.state.instance) } catch {
            closed = false
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
