import AppCore
import DesignSystem
import LocalStore
import PlanCore
import PlanUI
import Settings
import SwiftUI
import TripWizard
import TripWizardUI
import UIKit

struct AppTabs: View {
    enum Tab: Hashable { case today, trips, settings }
    @Environment(\.locale) private var locale
    var native: NativeSessionController?
    @State private var selection: Tab = .today
    @State private var home: PlanHomeModel?
    @State private var settingsHome = SettingsHomeModel()
    @State private var settingsPages: SettingsPagesModel?
    @State private var tripsPath: [TripPageRoute] = []
    @State private var path: [TripPageRoute] = []
    @State private var wizard: MemberWizardModel?
    @State private var wizardStore: MemberWizardStore?
    @State private var airportSearch: AirportSearchService?
    @State private var openingWizard = false
    private struct StepSelection: Identifiable {
        let tripID: String
        let blockID: String
        var id: String { "\(tripID)/\(blockID)" }
    }
    @State private var step: StepSelection?
    #if DEBUG
        @State private var showingLegend = false
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
                .sheet(isPresented: $showingLegend) { LegendSheet() }
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
            NavigationStack {
                SettingsHomeView(model: settingsHome)
                    .navigationDestination(for: SettingsDestination.self) { destination in
                        settingsDestination(destination)
                    }
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
                requestSync: { await native.sync?.requestSync() })
            settingsPages = pages
            pages.start()
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
                        wizard = MemberWizardModel(draft: recovered, store: recovery, search: search)
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
                    wizard = nil
                    wizardStore = nil
                    airportSearch = nil
                    return
                }
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

    @ViewBuilder private var today: some View {
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
                pastTrips: { selection = .trips }
            )
        } else if native != nil {
            PlanLoadingView(label: t("Loading today"))
        } else {
            seam(.today)
        }
    }
    @ViewBuilder private var trips: some View {
        if let home, let formatter = home.formatter {
            TripsScreen(
                trips: home.trips.trips, details: home.details.compactMapValues { $0.detail },
                now: home.trips.now, loading: !home.synced || !home.trips.hasLoaded, formatter: formatter,
                timeFormat: home.timeFormat, hidden: home.hidden,
                open: { tripsPath.append(TripPageRoute(tripID: $0)) },
                create: { openWizard() },
                refresh: { try? await native?.refreshNow() })
        } else if native != nil {
            ScrollView {
                TripsLoadingView().padding(PlanUITokens.space4).planPageRail()
            }.navigationTitle(t("My trips")).background(ColorToken.background.color)
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
                let draft = try await wizardStore.start()
                guard !Task.isCancelled, self.wizardStore === wizardStore else { return }
                wizard = MemberWizardModel(draft: draft, store: wizardStore, search: airportSearch)
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
