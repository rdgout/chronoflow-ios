import AppCore
import DesignSystem
import LocalStore
import PlanCore
import PlanUI
import Reminders
import SwiftUI
import Sync
import TripWizard

#if DEBUG
    import DataAccess
#endif

struct TripPageRoute: Hashable {
    var tripID: String
    var dayID: String? = nil
    var blockID: String? = nil
    var awaitingSync = false
    var notificationInputHash: String? = nil
    var notificationToken: UUID? = nil
}

struct TripPageSession {
    let snapshot: SessionSnapshot
    let database: AccountDatabase
    let permit: SessionMutationPermit
    let sync: SessionSync
}

struct TripPageDestination: View {
    let route: TripPageRoute
    var native: NativeSessionController?
    var onTrips: (() -> Void)?
    var onToday: (() -> Void)?
    var onSettings: (() -> Void)?
    var prepareWizard: ((String, TripWizardAction) async throws -> MemberWizardModel)?
    var presentWizard: ((MemberWizardModel) -> Void)?
    private let session: TripPageSession?
    @State private var model: TripPageModel?
    @State private var openedNotificationStep = false
    @State private var showingReminders = false
    @State private var showingActions = false
    @State private var openingWizard = false
    @State private var preparedWizard: MemberWizardModel?
    @State private var actionFailure: String?
    @Environment(\.locale) private var locale

    init(
        route: TripPageRoute, native: NativeSessionController? = nil, session: TripPageSession? = nil,
        onTrips: (() -> Void)? = nil, onToday: (() -> Void)? = nil, onSettings: (() -> Void)? = nil,
        prepareWizard: ((String, TripWizardAction) async throws -> MemberWizardModel)? = nil,
        presentWizard: ((MemberWizardModel) -> Void)? = nil
    ) {
        self.route = route
        self.native = native
        self.session = session
        self.onTrips = onTrips
        self.onToday = onToday
        self.onSettings = onSettings
        self.prepareWizard = prepareWizard
        self.presentWizard = presentWizard
        // Built here, not in the task, so the page and its bar exist on the push's first frame;
        // a bar swapped in mid-push fades in late.
        _model = State(initialValue: session.map { Self.makeModel(route: route, session: $0) })
    }

    private static func makeModel(route: TripPageRoute, session: TripPageSession) -> TripPageModel {
        var clock: any PlanClock = SystemPlanClock()
        #if DEBUG
            if UITestRuntime.environment["CF_PLAN_TEST_FREEZE_CLOCK"] == "1",
                (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true
            {
                clock = FixedPlanClock(now: Date())
            }
        #endif
        let sync = session.sync
        let snapshot = session.snapshot
        let page = TripPageModel(
            tripID: route.tripID, repository: TripRepository(database: session.database),
            retention: sync.retention, dayID: route.dayID, blockID: route.blockID, awaitingSync: route.awaitingSync,
            clock: clock, mutationPermit: session.permit,
            fetchDetail: { id in
                try await sync.fetchDetail(tripID: id, session: snapshot.session, epoch: snapshot.epoch)
            })
        #if DEBUG
            if (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true {
                page.timeline = UITestRuntime.environment["CF_PLAN_TEST_ROUTE"]?.hasSuffix(":list") != true
            }
        #endif
        return page
    }

    var body: some View {
        ZStack {
            ColorToken.background.color.ignoresSafeArea()
            if let model {
                tripPage(model)
            } else {
                Color.clear.tripPageLoadingBar()
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
        #if DEBUG
            .task(id: model?.plan.card != nil) {
                guard model?.plan.card != nil,
                    (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true,
                    UITestRuntime.environment["CF_WIZARD_BOARD_CAPTURE"] == "TripActions"
                else { return }
                showingActions = true
            }
        #endif
        .sheet(isPresented: $showingActions, onDismiss: presentPreparedWizard) {
            if let model, let card = model.plan.card {
                TripActionsSheet(card: card, detail: model.plan.detail, online: model.online, busy: openingWizard) {
                    action in
                    openWizard(action, model: model)
                }
                .overlay(alignment: .bottom) {
                    if let actionFailure {
                        FeedbackToast(
                            title: PageCopy(language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)(
                                actionFailure),
                            identifier: "trip.actions.failure", success: false)
                    }
                }
            }
        }
        .sheet(isPresented: $showingReminders) { RemindersDestination(native: native, firstTrip: true) }
        .task {
            let resolved: TripPageSession
            if let session {
                resolved = session
            } else {
                guard let native, let snapshot = await native.controller.activeSession(),
                    let database = await native.accounts.activeDatabase(), let sync = native.sync,
                    let permit = await native.controller.mutationPermit(for: snapshot)
                else { return }
                resolved = TripPageSession(snapshot: snapshot, database: database, permit: permit, sync: sync)
            }
            let snapshot = resolved.snapshot
            let sync = resolved.sync
            guard let native, await native.controller.activeSession() == snapshot, !Task.isCancelled else {
                return
            }
            let page = model ?? Self.makeModel(route: route, session: resolved)
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

    private func presentPreparedWizard() {
        guard let preparedWizard else { return }
        self.preparedWizard = nil
        presentWizard?(preparedWizard)
    }

    private func openWizard(_ action: TripAction, model: TripPageModel) {
        guard !openingWizard, model.online, let card = model.plan.card,
            TripActionsAvailability(
                canEdit: card.canEdit, canDuplicate: card.canDuplicate, online: model.online, busy: false
            ).enabled(action),
            let prepareWizard
        else { return }
        openingWizard = true
        actionFailure = nil
        Task {
            defer { openingWizard = false }
            do {
                preparedWizard = try await prepareWizard(route.tripID, action == .edit ? .edit : .duplicate)
                showingActions = false
            } catch is CancellationError { return } catch {
                actionFailure =
                    (error as? DataFailure) == .offline
                    ? "Needs a connection."
                    : action == .duplicate
                        ? "We could not duplicate this trip. Try again."
                        : "Something went wrong on our side. Try again in a moment."
            }
        }
    }

    private func tripPage(_ model: TripPageModel) -> TripPageView {
        var page = TripPageView(model: model, refresh: { try await native?.refreshNow() })
        page.onTrips = onTrips
        page.onToday = onToday
        page.onSettings = onSettings
        if model.plan.card != nil {
            page.onActions = {
                actionFailure = nil
                showingActions = true
            }
        }
        return page
    }
}
