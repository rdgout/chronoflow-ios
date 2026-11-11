import AppCore
import Foundation

public enum TripWizardAction: String, Sendable { case edit, duplicate }

extension WizardForm {
    public mutating func clearDuplicateDates() {
        identity = nil
        itinerary = nil
        for index in legs.indices {
            legs[index].departLocal = ""
            legs[index].arriveLocal = ""
            legs[index].leaveForAirportLocal = nil
        }
        for index in stays.indices {
            if stays[index].bedAvailableMode == "declared" { stays[index].bedAvailableMode = nil }
            stays[index].bedAvailableFromLocal = nil
            stays[index].checkOutLocal = nil
            stays[index].busyIntervals = []
        }
        end.nights = nil
        end.checkOutDate = nil
        if end.kind != "return_legs" { end = WizardEnd() }
        preparation.busyAnswered = false
        preparation.busyIntervals = []
    }
}

extension MemberWizardDraft {
    public var inputFingerprint: Data {
        var input = form.reviewInput(identity: nil, profile: state.profile.fields.isEmpty ? nil : state.profile)
        input.identity = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(input)) ?? Data()
    }

    public var hasChanges: Bool {
        state.edit != nil ? state.originalInput != inputFingerprint : state.entered
    }

    public mutating func loadTrip(_ snapshot: ApiTripInputSnapshot, id: String, action: TripWizardAction) throws {
        form = try WizardForm(snapshot: snapshot)
        guard !form.legs.isEmpty, form.legs.count <= WizardForm.maxFlights,
            (1...form.legs.count).contains(form.returnBoundary)
        else { throw DataFailure.server(status: nil) }
        airports = snapshot.airports
        state.fromLastTrip = false
        state.firstTrip = false
        state.homeChanged = form.end.kind == "return_legs" && form.legs.last?.toIata != form.legs.first?.fromIata
        state.returnRouteConfirmed = form.end.kind == "return_legs"
        state.copiedRoute =
            (form.legs.first?.fromCity ?? form.legs.first?.fromIata ?? "") + " → "
            + (form.legs.prefix(form.returnBoundary).last?.toCity ?? form.legs.prefix(form.returnBoundary).last?.toIata
                ?? "")
        if action == .edit {
            state.edit = TripEditContext(tripID: id, sourceRevision: snapshot.sourceRevision)
            state.originalForm = form
            state.snapshotStayEnd = snapshot.stayEnd
            state.profile = JSONObject()
            state.sleepNeeded = false
            state.entered = false
            state.step = .checking
            state.progressFloor = 0.95
            state.returnToReady = true
            state.originalInput = inputFingerprint
        } else {
            form.clearDuplicateDates()
            state.entered = true
            state.step = .outbound
        }
    }
}

extension MemberWizardModel {
    public var isEditing: Bool { draft.state.edit != nil }
    public var hasChanges: Bool { draft.hasChanges }
    public var checkingTitle: String {
        isEditing
            ? "Checking your changes"
            : draft.state.checkingAnswers == true ? "Checking your answers" : "Checking your trip"
    }

    func acceptSourceReload(_ snapshot: ApiTripInputSnapshot, price: ApiReviewPrice) throws {
        let form = try WizardForm(snapshot: snapshot)
        let before = draft.state.originalForm ?? draft.form
        var fields: [WizardPresentation.SourceChange.Field] = []
        if before.route().map(\.iata) != form.route().map(\.iata) { fields.append(.route) }
        if Array(before.legs.prefix(before.returnBoundary)) != Array(form.legs.prefix(form.returnBoundary)) {
            fields.append(.flight)
        }
        if Array(before.legs.dropFirst(before.returnBoundary)) != Array(form.legs.dropFirst(form.returnBoundary))
            || before.end != form.end
        {
            fields.append(.returnFlight)
        }
        if before.override != form.override { fields.append(.sleep) }
        if before.preparation != form.preparation || before.stays != form.stays { fields.append(.extras) }
        draft.form = form
        draft.airports = snapshot.airports
        draft.state.profile = JSONObject()
        draft.state.originalForm = form
        draft.state.snapshotStayEnd = snapshot.stayEnd
        draft.state.homeChanged = form.end.kind == "return_legs" && form.legs.last?.toIata != form.legs.first?.fromIata
        draft.state.returnRouteConfirmed = form.end.kind == "return_legs"
        draft.state.entered = false
        draft.state.originalInput = inputFingerprint
        if draft.state.review != nil {
            draft.state.sourceChange = WizardPresentation.SourceChange(
                form: form, fields: fields, price: price, previousPrice: draft.state.review?.price)
        }
    }
}
