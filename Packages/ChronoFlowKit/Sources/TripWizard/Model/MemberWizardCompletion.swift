import AppCore
import Foundation

public struct WizardSaveFailure: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case offline, server, throttle }
    public var kind: Kind
    public var retryAt: Date?
    public init(kind: Kind, retryAt: Date? = nil) {
        self.kind = kind
        self.retryAt = retryAt
    }
    public func seconds(at date: Date) -> Int {
        guard let retryAt else { return 0 }
        let remaining = ceil(retryAt.timeIntervalSince(date))
        guard remaining.isFinite, remaining > 0 else { return 0 }
        return remaining < Double(Int.max) ? Int(remaining) : Int.max
    }
}

public enum WizardCredits: Sendable, Equatable {
    case unlimited, free, oneFree, credits, unavailable
    public init(_ review: ApiTripReview) {
        if !review.canSave, review.saveBlockedReason != nil {
            self = .unavailable
        } else if review.price.unlimited {
            self = .unlimited
        } else if review.price.cost == 0 {
            self = .free
        } else if review.price.freeDirections.contains(.return) {
            self = .oneFree
        } else {
            self = .credits
        }
    }
}

extension MemberWizardModel {
    public var reviewInput: ApiTripReviewInput {
        draft.form.reviewInput(
            identity: draft.form.identity, profile: draft.state.profile.fields.isEmpty ? nil : draft.state.profile)
    }
    public var inputFingerprint: Data {
        var input = reviewInput
        input.identity = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(input)) ?? Data()
    }
    public var optionalPrompts: [ApiReviewPrompt] {
        (draft.state.review?.prompts ?? []).enumerated().filter { !$0.element.blocking }
            .sorted { left, right in
                left.element.required == right.element.required ? left.offset < right.offset : left.element.required
            }.map(\.element)
    }
    public var credits: WizardCredits? { draft.state.review.map(WizardCredits.init) }
    public var needsReadyReview: Bool {
        guard draft.state.savedTripId == nil else { return false }
        return draft.form.identity == nil || draft.state.checkedInput != inputFingerprint
            || draft.state.reviewedAt.map { now().timeIntervalSince($0) >= 1800 } != false
    }
    public var canSave: Bool {
        !reviewing && !persistenceFailed && !closed && retrySeconds == 0
            && (draft.state.savedTripId != nil || draft.state.review?.canSave == true)
    }

    public func editForm(_ update: (inout WizardForm) -> Void) {
        guard !closed, !reviewing, draft.state.step != .calculating else { return }
        update(&draft.form)
        changed()
    }

    public func openPrompt(_ id: String?) {
        guard !closed, !reviewing else { return }
        draft.state.promptSheetID = id
        persist()
    }

    public func answerOptional(_ prompt: ApiReviewPrompt, values: [String: JSONValue]) throws {
        guard !closed, !reviewing, let review = draft.state.review, optionalPrompts.contains(prompt) else { return }
        let input = try TripGenerationService.applyingAnswers(
            input: reviewInput, review: review, answers: [prompt.id: values])
        draft.form = try WizardForm(reviewInput: input, retained: draft.form)
        draft.state.profile = input.profile ?? JSONObject()
        draft.state.promptSheetID = nil
        changed()
    }

    public func revisit(_ step: MemberWizardStep, sleep: Bool = false) {
        guard !reviewing, draft.state.step == .ready else { return }
        draft.state.revisit = inputFingerprint
        draft.state.returnToReady = true
        if sleep, !draft.form.override.enabled {
            draft.form.override.enabled = true
            draft.form.override.habitualBed =
                draft.form.override.habitualBed
                ?? draft.state.profile["habitual_bed"]?.string ?? draft.state.savedProfile?["habitualBed"]?.string
            draft.form.override.habitualWake =
                draft.form.override.habitualWake
                ?? draft.state.profile["habitual_wake"]?.string ?? draft.state.savedProfile?["habitualWake"]?.string
        }
        go(step)
    }

    public func finishRoute(home: Bool = false) {
        if draft.state.revisit != nil, outboundComplete, draft.form.end.kind != "return_legs" || returnComplete {
            finishFlightInput()
        } else if home {
            finishReturnRoute()
        } else {
            go(.outbound)
        }
    }

    public func finishFineTune() {
        guard !closed, !reviewing else { return }
        if draft.state.checkedInput == inputFingerprint {
            draft.state.revisit = nil
            draft.state.returnToReady = nil
            go(.ready)
        } else {
            reviewInPlace()
        }
    }

    public func readyTick(force: Bool = false) {
        #if DEBUG
            if boardFrozen { return }
        #endif
        if let failure = draft.state.saveFailure { retrySeconds = failure.seconds(at: now()) }
        guard draft.state.step == .ready, !reviewing, draft.state.savedTripId == nil,
            force || needsReadyReview
        else { return }
        reviewInPlace()
    }

    public func resumeCompletion() {
        #if DEBUG
            if boardFrozen { return }
        #endif
        guard !resumed else { return }
        resumed = true
        if draft.state.step == .calculating {
            savePlan(recovering: true)
        } else if draft.state.step == .ready {
            readyTick(force: true)
        }
    }

    public func cancelInlineReview() {
        reviewTask?.cancel()
        reviewTask = nil
        reviewing = false
        cancelCheck()
    }

    private func reviewInPlace() {
        guard !reviewing, !closed else { return }
        reviewing = true
        draft.state.returnToReady = true
        let input = reviewInput
        let fingerprint = inputFingerprint
        let id = UUID()
        checkID = id
        let instance = "\(draft.state.instance)/\(id)"
        checkInstance = instance
        persist()
        reviewTask = Task { [weak self, generation] in
            do {
                guard let generation else { throw DataFailure.server(status: nil) }
                let result = try await generation.review(instance: instance, input: input)
                guard let self, !Task.isCancelled, self.checkID == id, !self.closed else { return }
                self.reviewing = false
                self.reviewTask = nil
                guard self.inputFingerprint == fingerprint else {
                    self.readyTick()
                    return
                }
                self.applyReview(result)
            } catch is CancellationError { return } catch {
                guard let self, self.checkID == id, !self.closed else { return }
                self.reviewing = false
                self.reviewTask = nil
                self.go(.checking)
                self.applyFailure(error as? DataFailure ?? .server(status: nil))
            }
        }
    }

    public func savePlan(recovering: Bool = false) {
        guard !closed, saveTask == nil, recovering || (draft.state.step == .ready && canSave) else { return }
        if !recovering, needsReadyReview {
            reviewInPlace()
            return
        }
        draft.state.saveFailure = nil
        draft.state.step = .calculating
        draft.state.promptSheetID = nil
        persist()
        let snapshot = draft
        let state = TripGenerationState(
            instance: snapshot.state.instance, input: reviewInput,
            review: snapshot.state.review, savedTripId: snapshot.state.savedTripId)
        saveTask = Task { [weak self, generation, store] in
            guard let self else { return }
            await self.flush()
            guard !self.persistenceFailed else {
                self.draft.state.step = .ready
                self.saveTask = nil
                return
            }
            do {
                guard let generation else { throw DataFailure.server(status: nil) }
                let result = try await generation.save(state) { id in
                    var saved = snapshot
                    saved.state.savedTripId = id
                    saved.state.revision += 1
                    try await store.persist(saved)
                }
                guard !Task.isCancelled, !self.closed else { return }
                self.draft.state.savedTripId = result.state.savedTripId
                switch result.outcome {
                case .saved(let id):
                    try await store.didSave(instance: snapshot.state.instance)
                    self.createdTripID = id
                    self.closed = true
                case .reReviewNeeded:
                    self.draft.form.identity = nil
                    self.draft.state.savedTripId = nil
                    self.draft.state.reviewedAt = nil
                    self.draft.state.checkedInput = nil
                    self.draft.state.step = .ready
                    self.persist()
                    self.readyTick(force: true)
                case .failed(let failure): self.saveFailed(failure)
                }
            } catch is CancellationError { return } catch {
                self.saveFailed(error as? DataFailure ?? .server(status: nil))
            }
            self.saveTask = nil
        }
    }

    private func saveFailed(_ failure: DataFailure) {
        let value: WizardSaveFailure
        switch failure {
        case .offline: value = WizardSaveFailure(kind: .offline)
        case .throttled(let seconds, _):
            value = WizardSaveFailure(
                kind: .throttle, retryAt: seconds.isFinite && seconds > 0 ? now().addingTimeInterval(seconds) : nil)
        default: value = WizardSaveFailure(kind: .server)
        }
        draft.state.saveFailure = value
        draft.state.step = .ready
        retrySeconds = value.seconds(at: now())
        persist()
    }
}
