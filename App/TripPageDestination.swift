import AppCore
import LocalStore
import PlanCore
import PlanUI
import SwiftUI
import Sync

struct TripPageRoute: Hashable {
    var tripID: String
    var dayID: String? = nil
    var blockID: String? = nil
    var awaitingSync = false
}

struct TripPageDestination: View {
    let route: TripPageRoute
    var native: NativeSessionController? = nil
    var onTrips: (() -> Void)?
    var onToday: (() -> Void)?
    var onSettings: (() -> Void)?
    @State private var model: TripPageModel?
    @State private var showingStep = false
    @State private var blockID: String?

    var body: some View {
        Group {
            if let model {
                tripPage(model)
            }
        }
        .task {
            guard let native, let snapshot = await native.controller.activeSession(),
                let database = await native.accounts.activeDatabase(), let sync = native.sync,
                let permit = await native.controller.mutationPermit(for: snapshot),
                await native.controller.activeSession() == snapshot, !Task.isCancelled
            else { return }
            let page = TripPageModel(
                tripID: route.tripID, repository: TripRepository(database: database), retention: sync.retention,
                dayID: route.dayID, blockID: route.blockID, awaitingSync: route.awaitingSync,
                mutationPermit: permit,
                fetchDetail: { id in
                    try await sync.fetchDetail(tripID: id, session: snapshot.session, epoch: snapshot.epoch)
                })
            model = page
            let events = Task {
                for await event in await sync.events() {
                    guard !Task.isCancelled else { return }
                    if case .finished(_, let epoch, let result) = event, epoch == snapshot.epoch,
                        result.state == .idle
                    {
                        page.syncCompleted = true
                    }
                }
            }
            defer {
                events.cancel()
                page.stop()
                model = nil
                showingStep = false
            }
            for await update in await native.controller.updates() {
                guard !Task.isCancelled, update.epoch == snapshot.epoch,
                    update.presence == .signedIn(accountID: snapshot.session.accountId)
                else { return }
            }
        }
        .sheet(isPresented: $showingStep) {
            if let model, let blockID {
                TripPageStepSheet(model: model, blockID: blockID)
            }
        }
    }

    private func tripPage(_ model: TripPageModel) -> TripPageView {
        var page = TripPageView(model: model)
        page.onBlock = openStep
        page.onTrips = onTrips
        page.onToday = onToday
        page.onSettings = onSettings
        return page
    }

    private func openStep(_ id: String) {
        blockID = id
        showingStep = true
    }
}

private struct TripPageStepSheet: View {
    let model: TripPageModel
    let blockID: String
    @State private var formatter: CopyLineFormatter?
    @State private var busy = false

    var body: some View {
        Group {
            if let formatter {
                StepSheet(
                    detail: model.plan.detail, blockID: blockID, now: model.plan.now, formatter: formatter,
                    timeFormat: model.plan.timeFormat, busy: busy
                ) { status in
                    guard !busy else { return }
                    busy = true
                    defer { busy = false }
                    try? await model.plan.setCheck(blockID: blockID, status: status)
                }
            }
        }.task { formatter = try? await CopyLineFormatter(catalog: CopyCatalog.load()) }
    }
}
