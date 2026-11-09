import AppCore
import DesignSystem
import LocalStore
import PlanCore
import PlanUI
import Reminders
import Settings
import SwiftUI
import TripWizard
import TripWizardUI
import UIKit

#if DEBUG
    import DataAccess
#endif

struct AppTabs: View {
    enum Tab: Hashable { case today, trips, settings }
    @Environment(\.locale) private var locale
    var native: NativeSessionController?
    @State private var selection: Tab = .today
    @State private var home: PlanHomeModel?
    @State private var settingsHome = SettingsHomeModel()
    @State private var settingsPages: SettingsPagesModel?
    @State private var settingsPath = NavigationPath()
    @State private var tripsPath: [TripPageRoute] = []
    @State private var path: [TripPageRoute] = []
    @State private var wizard: MemberWizardModel?
    @State private var wizardStore: MemberWizardStore?
    @State private var airportSearch: AirportSearchService?
    @State private var openingWizard = false
    @State private var todayFeedback = RefreshFeedbackModel()
    @State private var tripsFeedback = RefreshFeedbackModel()
    @State private var wizardGeneration: TripGenerationService?
    private struct StepSelection: Identifiable {
        let tripID: String
        let blockID: String
        var id: String { "\(tripID)/\(blockID)" }
    }
    @State private var step: StepSelection?
    #if DEBUG
        @State private var showingLegend = false
        @State private var showingReminders = false
        @State private var showingSettingsDelete = false
    #endif

    private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
    private func t(_ key: String) -> String { PlanStrings.text(key, language: language) }
    var body: some View {
        #if DEBUG
            tabs.planPageSafeArea()
                .onChange(of: home?.formatter != nil) { _, ready in
                    if ready, ProcessInfo.processInfo.environment["CF_PLAN_TEST_SHEET"] == "legend",
                        (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true
                    {
                        showingLegend = true
                    }
                }
                .onChange(of: home?.formatter != nil) { _, ready in
                    if ready, ProcessInfo.processInfo.arguments.contains("-cf.firstTripReminders"),
                        (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true
                    {
                        showingReminders = true
                    }
                }
                .sheet(isPresented: $showingReminders) { RemindersDestination(native: native, firstTrip: true) }
                .sheet(isPresented: $showingLegend) { LegendSheet() }
                .sheet(isPresented: $showingSettingsDelete) {
                    if let settingsPages { SettingsDeleteUITestSheet(store: settingsPages) }
                }
        #else
            tabs.planPageSafeArea()
        #endif
    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 26, *) {
            tabContent.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabContent
        }
    }

    @ViewBuilder private func settingsDestination(_ destination: SettingsDestination) -> some View {
        ZStack {
            ColorToken.background.color.ignoresSafeArea()
            if let settingsPages {
                switch destination {
                case .account: SettingsAccountView(store: settingsPages)
                case .profile: SettingsProfileView(store: settingsPages)
                case .bodyClock: SettingsBodyClockView(store: settingsPages)
                case .preferences:
                    SettingsPreferencesView(store: settingsPages) {
                        await native?.reminders.center.permission() ?? .undetermined
                    }
                case .security: SettingsSecurityView(store: settingsPages)
                case .reminders: RemindersDestination(native: native)
                case .plan:
                    SettingsPlanView(store: settingsPages, offline: settingsHome.offline) {
                        _ = try? await native?.refreshNow()
                    }
                default:
                    #if DEBUG
                        RoutePlaceholder(route: .settings, destination: destination.rawValue)
                    #else
                        EmptyView()
                    #endif
                }
            }
        }
    }

    private var tabContent: some View {
        TabView(selection: $selection) {
            NavigationStack(path: $path) {
                today
                    .navigationDestination(for: TripPageRoute.self) { tripDestination($0) }
            }
            .tabItem { Label(t("Today"), systemImage: "square.grid.2x2") }.tag(Tab.today)
            NavigationStack(path: $tripsPath) {
                trips.navigationDestination(for: TripPageRoute.self) { tripDestination($0) }
            }
            .tabItem { Label(t("My trips"), systemImage: "airplane") }.tag(Tab.trips)
            NavigationStack(path: $settingsPath) {
                SettingsHomeView(model: settingsHome)
                    .navigationDestination(for: SettingsDestination.self) { destination in
                        settingsDestination(destination)
                    }
                    #if DEBUG
                        .navigationDestination(for: String.self) { route in
                            if route == "language" {
                                SettingsLanguageView()
                            } else if let settingsPages {
                                SettingsSecurityUITestPage(
                                    store: settingsPages, route: route, setupPassword: MockScenarioValues.password)
                            }
                        }
                    #endif
            }
            .tabItem { Label(t("Settings"), systemImage: "gearshape") }.tag(Tab.settings)
        }
        .accessibilityIdentifier("app.tabs").tint(ColorToken.primary.color)
        .accessibilityElement(children: .contain)
        .fullScreenCover(isPresented: Binding(get: { wizard != nil }, set: { if !$0 { wizard = nil } })) {
            if let wizard { MemberWizardView(model: wizard) { self.wizard = nil } }
        }
        .task {
            guard let native, let snapshot = await native.controller.activeSession(),
                let database = await native.accounts.activeDatabase(),
                let permit = await native.controller.mutationPermit(for: snapshot),
                await native.controller.activeSession() == snapshot, !Task.isCancelled
            else { return }
            #if DEBUG
                do {
                    try await seedSettingsPending(
                        native: native, database: database, snapshot: snapshot, permit: permit)
                } catch {
                    assertionFailure("Settings UI test seed failed: \(error)")
                    return
                }
            #endif
            guard await native.controller.activeSession() == snapshot, !Task.isCancelled else { return }
            let settings = SettingsHomeModel(
                database: database, controller: native.controller, session: snapshot, sync: native.sync)
            settingsHome = settings
            settings.start()
            let pages = SettingsPagesModel(
                database: database, permit: permit,
                isCurrent: { await native.controller.activeSession() == snapshot },
                requestSync: { await native.sync?.requestSync() },
                delete: { password in
                    #if DEBUG
                        if (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true,
                            SettingsBoardCaptureFixture.state == "promptLocked"
                        {
                            throw DataFailure.throttled(retryAfterSeconds: 60, status: 429)
                        }
                    #endif
                    try await native.deleteAccount(password: password, session: snapshot)
                },
                security: { change in
                    #if DEBUG
                        if (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true {
                            try await SettingsBoardCaptureFixture.beforeSecurity()
                        }
                    #endif
                    return try await native.accountSecurity(change, session: snapshot)
                })
            settingsPages = pages
            pages.start()
            #if DEBUG
                let captureEnabled =
                    (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true
                SettingsBoardCaptureFixture.prepare(pages, enabled: captureEnabled)
                if captureEnabled, SettingsBoardCaptureFixture.state == "planOffline",
                    let source = await native.wizardDataSource(session: snapshot.session) as? DataAccess.MockDataSource
                {
                    await source.setOffline(true)
                    try? await native.refreshNow()
                }
                if (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true,
                    let route = ProcessInfo.processInfo.environment["CF_SETTINGS_ROUTE"]
                {
                    selection = .settings
                    switch route {
                    case "profile":
                        settingsPath.append(SettingsDestination.account)
                        settingsPath.append(SettingsDestination.profile)
                    case "language", "delete":
                        settingsPath.append(SettingsDestination.account)
                        if route == "delete" { showingSettingsDelete = true } else { settingsPath.append(route) }
                    case "password", "twoFactor", "twoFactorSetup":
                        settingsPath.append(SettingsDestination.security)
                        settingsPath.append(route)
                    default:
                        if let destination = SettingsDestination(rawValue: route) { settingsPath.append(destination) }
                    }
                }
            #endif
            var clock: any PlanClock = SystemPlanClock()
            #if DEBUG
                if ProcessInfo.processInfo.environment["CF_PLAN_TEST_FREEZE_CLOCK"] == "1",
                    (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true
                {
                    clock = FixedPlanClock(now: Date())
                }
            #endif
            let model = PlanHomeModel(
                repository: TripRepository(database: database), clock: clock, mutationPermit: permit)
            home = model
            model.start()
            let recovery = MemberWizardStore(database: database, permit: permit)
            if let source = await native.wizardDataSource(session: snapshot.session) {
                let search = airportSearch ?? AirportSearchService(source: source)
                guard await native.controller.activeSession() == snapshot, !Task.isCancelled else { return }
                wizardStore = recovery
                airportSearch = search
                do {
                    if wizard == nil, let recovered = try await recovery.recover(),
                        await native.controller.activeSession() == snapshot, !Task.isCancelled
                    {
                        let generation = try await native.wizardGenerationService(snapshot: snapshot)
                        guard await native.controller.activeSession() == snapshot, !Task.isCancelled else { return }
                        wizardGeneration = generation
                        wizard = MemberWizardModel(
                            draft: recovered, store: recovery, search: search, generation: generation)
                    }
                } catch { assertionFailure("Wizard recovery failed: \(error)") }
            }
            for await update in await native.controller.updates() {
                guard !Task.isCancelled, update.epoch == snapshot.epoch,
                    update.presence == .signedIn(accountID: snapshot.session.accountId)
                else {
                    model.stop()
                    settings.stop()
                    pages.stop()
                    home = nil
                    step = nil
                    await wizardGeneration?.cancel()
                    wizardGeneration = nil
                    wizard = nil
                    wizardStore = nil
                    airportSearch = nil
                    return
                }
            }
        }
        .task(id: locale) { await native?.reminders.setLanguage(language) }
        .onChange(of: native?.reminderTaps.pending, initial: true) { _, tap in
            guard let tap, let native else { return }
            native.reminderTaps.clear()
            Task {
                guard let current = await native.controller.activeSession(),
                    tap.accountID == nil || tap.accountID == current.session.accountId
                else { return }
                selection = .trips
                tripsPath = [
                    TripPageRoute(
                        tripID: tap.tripID, blockID: tap.blockID, notificationInputHash: tap.inputHash,
                        notificationToken: UUID())
                ]
            }
        }
        .onDisappear {
            home?.stop()
            settingsHome.stop()
            settingsPages?.stop()
            settingsPages = nil
            home = nil
        }
        .onChange(of: home?.hero?.card.id, initial: true) { _, _ in home?.selectHero() }
        .onChange(of: home?.trips.trips.filter { $0.status == .active }.map { $0.card.id }, initial: true) { _, ids in
            for id in ids ?? [] { _ = home?.detail(for: id) }
        }
        .sheet(item: $step) { selection in
            if let home, let formatter = home.formatter {
                StepSheet(
                    detail: home.details[selection.tripID]?.detail, blockID: selection.blockID, now: home.trips.now,
                    formatter: formatter, timeFormat: home.timeFormat, busy: home.changingCheck
                ) { status in
                    await home.setCheck(tripID: selection.tripID, blockID: selection.blockID, status: status)
                }
            }
        }

    }

    private func tripDestination(_ route: TripPageRoute) -> TripPageDestination {
        TripPageDestination(
            route: route, native: native,
            onTrips: {
                path.removeAll()
                tripsPath.removeAll()
                selection = .trips
            },
            onToday: {
                path.removeAll()
                tripsPath.removeAll()
                selection = .today
            },
            onSettings: { selection = .settings })
    }

    private var today: some View {
        ZStack { todayContent }.planRefreshFeedback(todayFeedback)
    }

    private func refreshToday() async {
        await todayFeedback.refresh { try await native?.refreshNow() }
    }

    @ViewBuilder private var todayContent: some View {
        if let home, let formatter = home.formatter {
            TodayScreen(
                trips: home.trips.trips, detail: home.selected?.detail, now: home.trips.now,
                loading: !home.synced || !home.trips.hasLoaded, formatter: formatter,
                hidden: home.hidden, timeFormat: home.timeFormat,
                openTrip: { path.append(TripPageRoute(tripID: $0)) },
                openStep: {
                    if let tripID = home.hero?.card.id {
                        step = StepSelection(tripID: tripID, blockID: $0)
                    }
                }, settings: { selection = .settings },
                pastTrips: { selection = .trips }, refresh: refreshToday
            )
        } else if native != nil {
            ScrollView {
                PlanLoadingView(label: t("Loading today")).padding(PlanUITokens.space4).planPageRail()
            }
            .planPageSafeArea()
            .refreshable { await refreshToday() }
            .scrollBounceBehavior(.always, axes: .vertical)
            .navigationTitle(t("Today")).background(ColorToken.background.color)
            .accessibilityElement(children: .contain).accessibilityIdentifier("today.screen")
        } else {
            seam(.today)
        }
    }
    private var trips: some View {
        ZStack { tripsContent }.planRefreshFeedback(tripsFeedback)
    }

    private func refreshTrips() async {
        await tripsFeedback.refresh { try await native?.refreshNow() }
    }

    @ViewBuilder private var tripsContent: some View {
        if let home, let formatter = home.formatter {
            TripsScreen(
                trips: home.trips.trips, details: home.details.compactMapValues { $0.detail },
                now: home.trips.now, loading: !home.synced || !home.trips.hasLoaded, formatter: formatter,
                timeFormat: home.timeFormat, hidden: home.hidden,
                open: { tripsPath.append(TripPageRoute(tripID: $0)) },
                create: { openWizard() }, refresh: refreshTrips)
        } else if native != nil {
            ScrollView {
                TripsLoadingView().padding(PlanUITokens.space4).planPageRail()
            }
            .planPageSafeArea()
            .refreshable { await refreshTrips() }
            .scrollBounceBehavior(.always, axes: .vertical)
            .navigationTitle(t("My trips")).background(ColorToken.background.color)
            .accessibilityElement(children: .contain).accessibilityIdentifier("trips.screen")
        } else {
            seam(.trips)
        }
    }

    private func openWizard() {
        guard !openingWizard, wizard == nil, let wizardStore, let airportSearch else { return }
        openingWizard = true
        Task {
            defer { openingWizard = false }
            do {
                guard let native, let snapshot = await native.controller.activeSession() else { return }
                let generation = try await native.wizardGenerationService(snapshot: snapshot)
                var draft = try await wizardStore.start()
                #if DEBUG
                    let capture =
                        (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true
                        ? ProcessInfo.processInfo.environment["CF_WIZARD_BOARD_CAPTURE"] : nil
                    if let capture { draft = WizardBoardCaptureSeed.draft(draft, board: capture, locale: locale) }
                #endif
                guard !Task.isCancelled, self.wizardStore === wizardStore else { return }
                guard await native.controller.activeSession() == snapshot else { return }
                wizardGeneration = generation
                wizard = MemberWizardModel(
                    draft: draft, store: wizardStore, search: airportSearch, generation: generation)
                #if DEBUG
                    if let capture, let wizard { WizardBoardCaptureSeed.freeze(wizard, board: capture) }
                #endif
            } catch is CancellationError { return } catch { assertionFailure("Wizard start failed: \(error)") }
        }
    }

    @ViewBuilder private func seam(_ route: Route) -> some View {
        #if DEBUG
            RoutePlaceholder(route: route)
        #else
            EmptyView()
        #endif
    }
}
