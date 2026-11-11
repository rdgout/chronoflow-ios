import AppCore
import DataAccess
import Foundation
import LocalStore
import Testing

@testable import TripWizard

@Suite struct TripWizardActionsTests {
    @Test(arguments: ["return_legs", "nights", "check_out"])
    func duplicateClearsEveryDateBoundAnswerAndRetainsRouteAndOtherAnswers(end: String) throws {
        var form = try WizardForm(input: generationInput())
        if end == "return_legs" {
            form.addReturn()
            form.legs[1].toIata = form.legs[0].fromIata
        } else {
            form.end.kind = end
        }
        form.end.nights = 9
        form.end.checkOutDate = "2030-10-22"
        form.identity = ApiReviewIdentity(token: "old", inputRevision: 8, reviewRevision: 7, sourceRevision: "old")
        form.override.enabled = true
        form.override.habitualBed = "00:30"
        form.preparation.busyAnswered = true
        form.preparation.busyIntervals = [WizardBusy(startLocal: "2030-10-10T09:00", endLocal: "2030-10-10T17:00")]
        for index in form.legs.indices {
            form.legs[index].seatWindow = "left"
            form.legs[index].seatLieFlat = true
            form.legs[index].leaveForAirportLocal = "2030-10-12T10:00"
            form.legs[index].airportTransferMin = 90
            form.stays[index].bedAvailableMode = "declared"
            form.stays[index].bedAvailableFromLocal = "2030-10-13T15:00"
            form.stays[index].checkOutLocal = "2030-10-22T11:00"
            form.stays[index].busyIntervals = form.preparation.busyIntervals
            form.stays[index].transferMode = "passenger"
        }
        let original = form
        form.clearDuplicateDates()
        #expect(form.identity == nil && form.itinerary == nil)
        #expect(form.legs.map(\.fromIata) == original.legs.map(\.fromIata))
        #expect(form.legs.map(\.toIata) == original.legs.map(\.toIata))
        #expect(
            form.legs.allSatisfy { $0.departLocal.isEmpty && $0.arriveLocal.isEmpty && $0.leaveForAirportLocal == nil })
        #expect(form.legs.allSatisfy { $0.seatWindow == "left" && $0.seatLieFlat && $0.airportTransferMin == 90 })
        #expect(
            form.stays.allSatisfy {
                $0.bedAvailableMode == nil && $0.bedAvailableFromLocal == nil && $0.checkOutLocal == nil
                    && $0.busyIntervals.isEmpty && $0.transferMode == "passenger"
            })
        #expect(form.preparation.busyIntervals.isEmpty && !form.preparation.busyAnswered)
        #expect(form.preparation.days == original.preparation.days && form.override == original.override)
        #expect(form.end.kind == (end == "return_legs" ? "return_legs" : "one_way"))
        #expect(form.end.nights == nil && form.end.checkOutDate == nil)
    }

    @Test @MainActor func editStartsAtCheckingReviewsImmediatelyAndUntouchedEditCannotSave() async throws {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        let source = try GenerationSource()
        let draft = try await store.startTrip(id: "trip", action: .edit, source: source)
        #expect(draft.state.step == .checking && !draft.state.sleepNeeded && !draft.hasChanges)
        #expect(draft.state.returnToReady == true && draft.form.identity == nil)
        #expect(try await store.recover() == draft)
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let clock = CheckingTestClock()
        let model = MemberWizardModel(
            draft: draft, store: store, search: noAirportSearch(), now: { .distantPast }, generation: service,
            checkingClock: clock.clock)
        model.resumeChecking()
        try await eventually { await source.count("review") == 1 && clock.waiterCount >= 2 }
        #expect(await source.operations == ["input", "input", "review"])
        #expect(model.checkingTitle == "Checking your changes")
        clock.advance(to: 1.2)
        try await eventually { clock.deadlines.contains(1.5) }
        clock.advance(to: 1.5)
        try await eventually { model.draft.state.step == .ready }
        #expect(!model.hasChanges && !model.canSave)
        model.savePlan()
        #expect(await source.count("update") == 0)
        #expect(await source.count("save") == 0)
        try await model.discard()
        #expect(try await store.recover() == nil)
        try await database.close()
    }

    @Test @MainActor func changedSourceReloadsInputAirportsBaselineAndRevisionBeforeUpdate() async throws {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        let source = try GenerationSource()
        var initial = try generationInput()
        initial.preparationDays = 3
        let original = ApiTripInputSnapshot(input: initial, sourceRevision: "one", airports: [:])
        await source.queueSnapshots([original, original])
        let draft = try await store.startTrip(id: "trip", action: .edit, source: source)
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let model = MemberWizardModel(
            draft: draft, store: store, search: noAirportSearch(), now: { .distantPast }, generation: service)
        let first = try await service.review(
            instance: "initial", input: model.reviewInput, edit: model.draft.state.edit)
        model.applyReview(first)
        model.editForm { $0.preparation.days = 1 }
        #expect(model.hasChanges)
        var changed = initial
        changed.preparationDays = 2
        changed.outbound.legs[0].flightNumber = "NEW123"
        let airport = wizardAirport("HND", city: "Tokio", zone: "Asia/Tokyo")
        let updated = ApiTripInputSnapshot(input: changed, sourceRevision: "two", airports: ["HND": airport])
        await source.queueSnapshots([updated])
        model.readyTick(force: true)
        try await eventually { !model.reviewing && model.draft.state.edit?.sourceRevision == "two" }
        #expect(model.reviewInput.input == changed && model.draft.airports["HND"] == airport)
        #expect(model.draft.form.legs[0].flightNumber == "NEW123")
        #expect(!model.hasChanges && !model.canSave)
        #expect(model.draft.state.sourceChange?.fields.contains(.flight) == true)
        #expect(await source.reviewInputs.last?.identity == nil)
        await model.flush()
        let recovered = try #require(try await store.recover())
        #expect(
            recovered.state.edit == model.draft.state.edit
                && recovered.state.sourceChange == model.draft.state.sourceChange)
        #expect(!recovered.hasChanges)
        await source.queueSnapshots([updated])
        model.editForm { $0.preparation.days = 1 }
        model.readyTick()
        try await eventually { !model.reviewing && !model.needsReadyReview }
        #expect(model.canSave && model.hasChanges)
        #expect(model.draft.state.sourceChange == nil)
        model.savePlan()
        try await eventually { model.createdTripID == "trip" }
        #expect(await source.count("update") == 1)
        #expect(await source.count("save") == 0)
        #expect(await source.lastEdit == TripEditContext(tripID: "trip", sourceRevision: "two"))
        try await database.close()
    }

    @Test(arguments: [DataFailure.offline, .server(status: 500)]) @MainActor
    func editSaveFailureKeepsChangesAndRetryUpdatesTheSameTrip(failure: DataFailure) async throws {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        let source = try GenerationSource()
        var draft = try await store.startTrip(id: "trip", action: .edit, source: source)
        draft.form.preparation.days = 1
        draft.state.step = .ready
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let model = MemberWizardModel(
            draft: draft, store: store, search: noAirportSearch(), now: { .distantPast }, generation: service)
        model.applyReview(try await service.review(instance: "edit", input: model.reviewInput, edit: draft.state.edit))
        await source.configure(saveFailure: failure)
        model.savePlan()
        await model.saveTask?.value
        #expect(model.draft.state.step == .ready && model.hasChanges && model.createdTripID == nil)
        #expect(model.draft.state.saveFailure?.kind == (failure == .offline ? .offline : .server))
        #expect(await source.count("save") == 0)
        await source.configure()
        model.savePlan()
        await model.saveTask?.value
        #expect(model.createdTripID == "trip")
        #expect(await source.count("update") == 2)
        try await database.close()
    }

    @Test @MainActor func duplicateStartsOutboundAndSavesFreshWithoutEditingOriginalAgainstMock() async throws {
        let now = Date(timeIntervalSince1970: 1_793_750_400)
        let seed = try MockAppSeed.make(now: now)
        let account = try #require(seed.accounts.values.first { $0.twoFactorCode == nil })
        let source = MockDataSource(seed: seed, now: { now }, sleep: { _ in })
        _ = try await source.signIn(
            PasswordSignInInput(
                email: account.snapshot.email, password: account.password, deviceID: UUID().uuidString,
                deviceName: "Tests"))
        let trip = try #require(try await source.fetchTrips().first)
        let original = try await source.tripInput(id: trip.card.id)
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        let draft = try await store.startTrip(id: trip.card.id, action: .duplicate, source: source)
        #expect(draft.state.step == .outbound && draft.state.edit == nil && draft.form.identity == nil)
        #expect(draft.state.copiedRoute != nil && draft.hasChanges && !draft.state.firstTrip)
        #expect(draft.form.legs.allSatisfy { $0.departLocal.isEmpty && $0.arriveLocal.isEmpty })
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let model = MemberWizardModel(
            draft: draft, store: store, search: noAirportSearch(), now: { .distantPast }, generation: service)
        model.editForm {
            for index in $0.legs.indices {
                let leg = original.input.outbound.legs + (original.input.return?.legs ?? [])
                $0.legs[index].departLocal = WizardDateTime.string(
                    WizardDateTime.date(leg[index].departLocal)!.addingTimeInterval(30 * 86400))
                $0.legs[index].arriveLocal = WizardDateTime.string(
                    WizardDateTime.date(leg[index].arriveLocal)!.addingTimeInterval(30 * 86400))
            }
        }
        model.draft.state.profile = JSONObject(["age_band": .string("18_64"), "shift_work": .bool(false)])
        #expect(model.reviewInput.identity == nil)
        let review = try await service.review(instance: "duplicate", input: model.reviewInput)
        model.applyReview(review)
        if model.draft.state.step == .fineTune { model.finishFineTune() }
        #expect(model.draft.state.step == .ready && model.canSave)
        model.savePlan()
        await model.saveTask?.value
        let created = try #require(model.createdTripID)
        #expect(created != trip.card.id)
        #expect(try await source.tripInput(id: trip.card.id) == original)
        #expect(try await source.tripInput(id: created).input == model.reviewInput.input)
        try await database.close()
    }
}
