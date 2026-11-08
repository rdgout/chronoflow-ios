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
    @State private var stepTripID: String?
    @State private var stepID: String?
    @State private var showingStep = false
    #if DEBUG
        @State private var showingLegend = false
    #endif

    private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
    private func t(_ key: String) -> String { PlanStrings.text(key, language: language) }
    var body: some View {
        #if DEBUG
            tabs
                .onChange(of: home?.formatter != nil) { _, ready in
                    if ready, ProcessInfo.processInfo.environment["CF_PLAN_TEST_SHEET"] == "legend",
                        (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true
                    {
                        showingLegend = true
                    }
                }
                .sheet(isPresented: $showingLegend) { LegendSheet() }
        #else
            tabs
        #endif
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            NavigationStack(path: $path) {
                today
                    .navigationDestination(for: TripPageRoute.self) { TripPageDestination(route: $0, native: native) }
            }
            .tabItem { Label(t("Today"), systemImage: "sun.max") }.tag(Tab.today)
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
                await native.controller.activeSession() == snapshot, !Task.isCancelled
            else { return }
            let model = PlanHomeModel(repository: TripRepository(database: database))
            home = model
            model.start()
        }
        .onDisappear {
            home?.stop()
            home = nil
        }
        .onChange(of: home?.hero?.card.id, initial: true) { _, _ in home?.selectHero() }
        .onChange(of: home?.trips.trips.filter { $0.status == .active }.map { $0.card.id }, initial: true) { _, ids in
            for id in ids ?? [] { _ = home?.detail(for: id) }
        }
        .sheet(isPresented: $showingStep, onDismiss: clearStep) {
            if let home, let formatter = home.formatter, let stepID, let stepTripID {
                StepSheet(
                    detail: home.details[stepTripID]?.detail, blockID: stepID, now: home.trips.now,
                    formatter: formatter, timeFormat: home.timeFormat, busy: home.changingCheck
                ) { status in
                    await home.setCheck(tripID: stepTripID, blockID: stepID, status: status)
                }
            }
        }

    }

    private func clearStep() {
        stepID = nil
        stepTripID = nil
    }

    @ViewBuilder private var today: some View {
        if let home, let formatter = home.formatter {
            TodayScreen(
                trips: home.trips.trips, detail: home.selected?.detail, now: home.trips.now,
                loading: !home.synced || !home.trips.hasLoaded, formatter: formatter,
                hidden: home.hidden, timeFormat: home.timeFormat,
                openTrip: { path.append(TripPageRoute(tripID: $0)) },
                openStep: {
                    stepTripID = home.hero?.card.id
                    stepID = $0
                    showingStep = true
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
            PlanLoadingView(label: t("Loading your trips"))
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
