import AppCore
import DesignSystem
import LocalStore
import PlanCore
import PlanUI
import Reminders
import SwiftUI
import Sync

struct TripPageRoute: Hashable {
    var tripID: String
    var dayID: String? = nil
    var blockID: String? = nil
    var awaitingSync = false
    var notificationInputHash: String? = nil
    var notificationToken: UUID? = nil
}

struct TripPageDestination: View {
    let route: TripPageRoute
    var native: NativeSessionController? = nil
    var onTrips: (() -> Void)?
    var onToday: (() -> Void)?
    var onSettings: (() -> Void)?
    @State private var model: TripPageModel?
    @State private var openedNotificationStep = false
    @State private var showingReminders = false

    var body: some View {
        ZStack {
            ColorToken.background.color.ignoresSafeArea()
            if let model {
                tripPage(model)
            }
        }
        .task(id: model?.plan.detail?.plan.meta.inputHash) {
            guard !openedNotificationStep, let model, let detail = model.plan.detail, let blockID = route.blockID,
                let hash = route.notificationInputHash, hash == detail.plan.meta.inputHash,
                detail.plan.blocks.contains(where: { $0.id == blockID }),
                let catalog = try? await CopyCatalog.load(), !Task.isCancelled
            else { return }
            openedNotificationStep = true
            model.selectBlock(blockID, formatter: CopyLineFormatter(catalog: catalog))
        }
        .task(id: model != nil) {
            guard model != nil, let native, let snapshot = await native.controller.activeSession(),
                let database = await native.accounts.activeDatabase(),
                let permit = await native.controller.mutationPermit(for: snapshot)
            else { return }
            let offer = FirstTripRemindersOffer(database: database, permit: permit)
            do {
                for try await _ in try await SettingsRepository(database: database).values() {
                    guard !Task.isCancelled, await native.controller.activeSession() == snapshot else { return }
                    let permission = await native.reminders.center.permission()
                    guard let show = try await offer.consume(permission: permission) else { continue }
                    guard !Task.isCancelled, await native.controller.activeSession() == snapshot else { return }
                    showingReminders = show
                    return
                }
            } catch is CancellationError { return } catch {
                assertionFailure("First-trip reminders offer failed: \(error)")
            }
        }
        .sheet(isPresented: $showingReminders) { RemindersDestination(native: native, firstTrip: true) }
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
            }
            for await update in await native.controller.updates() {
                guard !Task.isCancelled, update.epoch == snapshot.epoch,
                    update.presence == .signedIn(accountID: snapshot.session.accountId)
                else { return }
            }
        }
    }

    private func tripPage(_ model: TripPageModel) -> TripPageView {
        var page = TripPageView(model: model, refresh: { try await native?.refreshNow() })
        page.onTrips = onTrips
        page.onToday = onToday
        page.onSettings = onSettings
        return page
    }
}
