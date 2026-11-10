import AppCore
import Foundation

extension MemberWizardModel {
    public var lastInputStep: MemberWizardStep {
        if mode == .guest { return .sleep }
        if let step = draft.state.lastInputStep { return step }
        if draft.state.sleepNeeded { return .sleep }
        return draft.form.end.kind == "return_legs" ? .returnFlight : .returnChoice
    }
    public var returnComplete: Bool {
        draft.form.end.kind == "return_legs"
            && draft.form.legs.dropFirst(draft.form.returnBoundary).allSatisfy {
                !$0.toIata.isEmpty && WizardDateTime.date($0.departLocal) != nil
                    && WizardDateTime.date($0.arriveLocal) != nil
            }
    }
    public var sleepComplete: Bool {
        WizardDateTime.isTime(draft.state.profile["habitual_bed"]?.string)
            && WizardDateTime.isTime(draft.state.profile["habitual_wake"]?.string)
            && draft.state.profile["chronotype"] != nil
    }
    public var currentQuestion: ApiReviewPrompt? {
        let questions = draft.state.questions ?? []
        let index = draft.state.questionIndex ?? 0
        return questions.indices.contains(index) ? questions[index] : nil
    }
    public var progress: Double { max(draft.state.progressFloor ?? 0, stepProgress) }
    private var stepProgress: Double {
        if mode == .guest { return guestStepProgress }
        return switch draft.state.step {
        case .whereTo: whereComplete ? 0.15 : 0.08
        case .outbound: outboundComplete ? 0.30 : 0.22
        case .returnChoice, .returnRoute, .returnFlight: 0.45
        case .sleep: 0.50
        case .checking, .excluded: draft.state.checkingAnswers == true ? 0.70 : 0.52
        case .question:
            0.54 + 0.16 * Double(draft.state.questionIndex ?? 0) / Double(max(1, draft.state.questions?.count ?? 1))
        case .continuation, .fineTune: 0.80
        case .ready: 0.95
        case .calculating: 1
        }
    }

    public func chooseReturn(_ kind: String) {
        guard mode == .member, !closed, !choicePending, draft.state.step == .returnChoice else { return }
        if kind == "return_legs" {
            if draft.form.end.kind != kind {
                draft.form.end.nights = nil
                draft.form.end.checkOutDate = nil
                draft.form.addReturn()
                draft.state.returnRouteConfirmed = false
                draft.state.homeChanged = false
                let first = draft.form.legs[0]
                draft.form.updateLeg(draft.form.legs.count - 1) {
                    $0.toIata = first.fromIata
                    $0.toCity = first.fromCity
                }
            }
            guard draft.form.end.kind == kind else { return }
        } else if kind == "one_way" {
            draft.form.removeReturn()
            draft.form.end = WizardEnd()
            draft.state.returnRouteConfirmed = nil
            draft.state.homeChanged = false
        } else {
            guard kind == draft.form.end.kind, ["nights", "check_out"].contains(kind) else { return }
        }
        changed()
        advanceChoice { model in
            if kind == "return_legs" { model.go(.returnRoute) } else { model.finishFlightInput() }
        }
    }

    public func finishReturn() -> Bool {
        guard !closed, !persistenceFailed, returnComplete else { return false }
        draft.fieldErrors = WizardFlightRules.errors(
            form: draft.form, airports: draft.airports, now: now(), checkPast: false)
        persist()
        return draft.fieldErrors.isEmpty
    }

    public func setSleep(_ field: String, value: JSONValue) {
        guard ["habitual_bed", "habitual_wake", "chronotype"].contains(field), !closed else { return }
        draft.state.profile[field] = value
        draft.state.sleepCompleted = false
        changed()
    }

    @discardableResult public func finishSleep() -> Bool {
        guard !closed, !persistenceFailed, sleepComplete else { return false }
        let bed = draft.state.profile["habitual_bed"]!.string!
        let wake = draft.state.profile["habitual_wake"]!.string!
        func minutes(_ value: String) -> Int { Int(value.prefix(2))! * 60 + Int(value.suffix(2))! }
        let duration = (minutes(wake) - minutes(bed) + 1440) % 1440
        guard (180...840).contains(duration) else {
            draft.fieldErrors["profile.habitual_bed"] = FieldMessage(key: "Check your bedtime and wake-up time.")
            persist()
            return false
        }
        draft.state.sleepCompleted = true
        beginChecking()
        return true
    }

    public func finishFlightInput() {
        if draft.state.revisit != nil, draft.state.revisit == inputFingerprint {
            draft.state.revisit = nil
            draft.state.returnToReady = nil
            go(.ready)
            return
        }
        if draft.state.sleepNeeded { go(.sleep) } else { beginChecking() }
    }

    public func beginChecking() {
        updateRetrySeconds()
        guard !closed, !persistenceFailed, !choicePending, retrySeconds == 0 else { return }
        guard draft.state.step != .checking || checkTask == nil || checking.failure != nil else { return }
        if draft.state.sleepNeeded, draft.state.sleepCompleted != true {
            go(.sleep)
            return
        }
        if [.returnChoice, .returnFlight, .sleep].contains(draft.state.step) {
            draft.state.lastInputStep = draft.state.step
        }
        go(.checking)
        runCheck()
    }

    public func resumeChecking() {
        guard draft.state.step == .checking, checkTask == nil, checking.failure == nil else { return }
        if draft.state.sleepNeeded, draft.state.sleepCompleted != true {
            go(.sleep)
            return
        }
        runCheck()
    }

    public func cancelCheck() {
        checkID = UUID()
        checkTask?.cancel()
        checkTask = nil
        guard let instance = checkInstance else { return }
        checkInstance = nil
        let generation = generation
        Task {
            await generation?.cancelReviews(instance: instance)
        }
    }

    private func runCheck() {
        cancelCheck()
        checking = WizardCheckingProgress()
        draft.state.sourceChange = nil
        restartRetryCountdown()
        let id = UUID()
        checkID = id
        let input = draft.form.reviewInput(
            identity: draft.form.identity, profile: draft.state.profile.fields.isEmpty ? nil : draft.state.profile)
        let instance = "\(draft.state.instance)/\(id)"
        checkInstance = instance
        let generation = generation
        let edit = draft.state.edit
        checkTask = Task { [weak self, checkingClock] in
            guard !Task.isCancelled else { return }
            await WizardChecking.run(
                clock: checkingClock,
                request: {
                    guard let generation else { throw DataFailure.server(status: nil) }
                    return try await generation.review(instance: instance, input: input, edit: edit)
                }
            ) { [weak self] event in
                guard let self, self.checkID == id, !self.closed, self.draft.state.step == .checking else { return }
                switch event {
                case .tick(let count): self.checking.ticks = max(self.checking.ticks, count)
                case .slow: self.checking.slow = true
                case .complete(let result): self.applyReview(result)
                case .failed(let failure): self.applyFailure(failure)
                }
            }
            guard let self, self.checkID == id else { return }
            if self.checkID == id { self.checkTask = nil }
        }
    }

    func applyReview(_ result: TripGenerationReviewResult) {
        do {
            let unchangedInput = draft.state.checkedInput == inputFingerprint
            if let snapshot = result.sourceSnapshot { try acceptSourceReload(snapshot, price: result.review.price) }
            if let edit = result.edit { draft.state.edit = edit }
            draft.form = try WizardForm(reviewInput: result.input, retained: draft.form)
            draft.form.itinerary = result.review.itinerary
            draft.state.profile = ProfilePreferences.request(result.input.profile ?? JSONObject())
            let previous = draft.state.review
            draft.state.review = result.review
            draft.state.updated =
                unchangedInput && previous != nil
                && (previous?.summary != result.review.summary || previous?.price.cost != result.review.price.cost
                    || previous?.price.state != result.review.price.state
                    || previous?.price.unlimited != result.review.price.unlimited
                    || previous?.price.freeDirections != result.review.price.freeDirections)
            draft.state.reviewedAt = now()
            draft.state.checkedInput = inputFingerprint
            draft.state.saveFailure = nil
            checking = WizardCheckingProgress()
            restartRetryCountdown()
            if mode == .member, draft.state.sleepCompleted == true { draft.state.sleepNeeded = false }
            draft.fieldErrors = [:]
            let errors = WizardFlightRules.errors(
                form: draft.form, airports: draft.airports, now: now(), checkPast: true, mode: mode)
            if !errors.isEmpty {
                draft.fieldErrors = errors
                go(WizardJourney.errorStep(errors, form: draft.form))
                return
            }
            let questions = result.review.prompts.filter { $0.blocking && ProfilePreferences.isSupported($0) }
            draft.state.questions = questions
            draft.state.questionIndex = 0
            if result.review.status == .noPlan {
                go(.excluded)
            } else if !questions.isEmpty {
                go(.question)
            } else {
                let destination: MemberWizardStep =
                    draft.state.returnToReady == true || (mode == .member && optionalPrompts.isEmpty)
                    ? .ready : .fineTune
                draft.state.returnToReady = nil
                draft.state.revisit = nil
                go(destination)
            }
        } catch { applyFailure(.server(status: nil)) }
    }

    func applyFailure(_ failure: DataFailure) {
        switch failure {
        case .validation(let fields, _), .profileInvalid(let fields):
            draft.fieldErrors = WizardJourney.errors(fields, form: draft.form)
            if draft.fieldErrors.keys.contains(where: {
                $0.hasPrefix("override.") || $0.hasPrefix("preparation.") || $0.hasPrefix("stays.")
                    || $0.contains("seatWindow")
            }) {
                go(.fineTune)
            } else if draft.fieldErrors.keys.contains(where: { $0.hasPrefix("profile.") }) {
                let sleepFields = ["profile.habitual_bed", "profile.habitual_wake", "profile.chronotype"]
                go(draft.fieldErrors.keys.contains(where: sleepFields.contains) ? .sleep : .fineTune)
            } else {
                go(WizardJourney.errorStep(draft.fieldErrors, form: draft.form))
            }
        default:
            checking.failure = failure
            checking.retryAt = nil
            if case .throttled(let seconds, _) = failure, seconds.isFinite, seconds > 0 {
                checking.retryAt = checkingClock.now() + seconds
            }
            restartRetryCountdown()
            persist()
        }
    }

    public func answerQuestion(_ value: JSONValue) {
        guard !closed, !choicePending, let prompt = currentQuestion,
            let field = prompt.fields.first, prompt.fields.count == 1, prompt.target == .profile,
            (prompt.kind == .screening && field == "shift_work" && prompt.shape.kind == .boolean
                && (value == .bool(true) || value == .bool(false)))
                || (prompt.kind == .ageBand && field == "age_band" && prompt.shape.options.contains(value.string ?? ""))
        else { return }
        draft.state.profile[field] = value
        changed()
        advanceChoice { model in
            let index = (model.draft.state.questionIndex ?? 0) + 1
            if index < (model.draft.state.questions?.count ?? 0) {
                model.draft.state.questionIndex = index
                model.go(.question)
            } else {
                model.draft.state.checkingAnswers = true
                model.beginChecking()
            }
        }
    }

    public func navigateToQuestion(_ index: Int) {
        guard (draft.state.questions ?? []).indices.contains(index) else { return }
        draft.state.questionIndex = index
        go(.question)
    }

    public func backFromQuestion() {
        let index = draft.state.questionIndex ?? 0
        if index > 0 {
            draft.state.questionIndex = index - 1
            go(.question)
        } else {
            go(lastInputStep)
        }
    }

    public var exclusionWasSaved: Bool {
        let body = draft.state.savedProfile
        return (draft.state.profile["age_band"] == nil && body?["ageBand"] == .string("under_18"))
            || (draft.state.profile["shift_work"] == nil && body?["shiftWork"] == .bool(true))
    }

    public func changeExcludedAnswers() {
        if mode == .guest {
            draft.state.profile["age_band"] = .null
            draft.state.profile["shift_work"] = .null
            draft.state.checkingAnswers = false
            draft.state.returnToReady = nil
            draft.state.questions = guestScreeningQuestions
            draft.state.questionIndex = 0
            go(.question)
            return
        }
        for (field, stored) in [
            ("age_band", "ageBand"), ("shift_work", "shiftWork"),
        ] {
            let value = draft.state.profile[field] ?? draft.state.savedProfile?[stored]
            if value == .bool(true) || (field == "age_band" && value == .string("under_18")) {
                draft.state.profile[field] = .null
            }
        }
        draft.state.checkingAnswers = true
        beginChecking()
    }

    private func advanceChoice(_ advance: @escaping @MainActor (MemberWizardModel) -> Void) {
        choicePending = true
        let deadline = checkingClock.now() + 0.25
        choiceTask = Task { [weak self, checkingClock] in
            do {
                try await checkingClock.sleepUntil(deadline)
                try Task.checkCancellation()
            } catch { return }
            guard let self, !self.closed else { return }
            self.choicePending = false
            advance(self)
        }
    }
}
