import AppCore
import DesignSystem
import LocalStore
import PlanCore
import PlanUI
import SwiftUI
import UIKit

struct AppTabs: View {
    enum Tab: Hashable { case today, trips, settings }
    @Environment(\.locale) private var locale
    var native: NativeSessionController?
    @State private var selection: Tab = .today
    @State private var home: PlanHomeModel?
    @State private var tripsPath: [TripPageRoute] = []
    @State private var path: [TripPageRoute] = []
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

    private var tabContent: some View {
        TabView(selection: $selection) {
            NavigationStack(path: $path) {
                today
                    .navigationDestination(for: TripPageRoute.self) { TripPageDestination(route: $0, native: native) }
            }
            .tabItem { Label(t("Today"), systemImage: "square.grid.2x2") }.tag(Tab.today)
            NavigationStack(path: $tripsPath) {
                trips.navigationDestination(for: TripPageRoute.self) { TripPageDestination(route: $0, native: native) }
            }
            .tabItem { Label(t("My trips"), systemImage: "airplane") }.tag(Tab.trips)
            NavigationStack { seam(.settings) }
                .tabItem { Label(t("Settings"), systemImage: "gearshape") }.tag(Tab.settings)
        }
        .accessibilityIdentifier("app.tabs").tint(ColorToken.primary.color)
        .task {
            guard let native, let snapshot = await native.controller.activeSession(),
                let database = await native.accounts.activeDatabase(),
                let permit = await native.controller.mutationPermit(for: snapshot),
                await native.controller.activeSession() == snapshot, !Task.isCancelled
            else { return }
            var clock: any PlanClock = SystemPlanClock()
            #if DEBUG
                if ProcessInfo.processInfo.environment["CF_PLAN_TEST_FREEZE_CLOCK"] == "1",
                    (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true
                {
                    clock = AuditPlanClock()
                }
            #endif
            let model = PlanHomeModel(
                repository: TripRepository(database: database), clock: clock, mutationPermit: permit)
            home = model
            model.start()
            for await update in await native.controller.updates() {
                guard !Task.isCancelled, update.epoch == snapshot.epoch,
                    update.presence == .signedIn(accountID: snapshot.session.accountId)
                else {
                    model.stop()
                    home = nil
                    step = nil
                    return
                }
            }
        }
        .onDisappear {
            home?.stop()
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
                refresh: { try? await native?.refreshNow() })
        } else if native != nil {
            ScrollView {
                TripsLoadingView().padding(PlanUITokens.space4)
            }.planPageRail().navigationTitle(t("My trips")).background(ColorToken.background.color)
        } else {
            seam(.trips)
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

#if DEBUG
    private struct AuditPlanClock: PlanClock {
        nonisolated func values() async -> AsyncStream<Date> { AsyncStream { $0.finish() } }
    }
#endif
