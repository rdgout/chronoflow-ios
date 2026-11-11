import XCTest

@MainActor enum PlanUIFlow {
    static let tripID = "0199a3c0-0000-7000-8000-000000000001"
    static let stepID = "sleep-sleep-29865450"
    static let blockTripID = "0199a3c0-0000-7000-8000-000000000002"
    static let blockID = "caffeine-caffeine_serving-29864460"
}

@MainActor func launchPlanAccount(
    presentLegend: Bool = false, freezePlanClock: Bool = false, emptyTrips: Bool = false,
    appearance: XCUIDevice.Appearance? = nil, route: String? = nil, stepID: String? = nil,
    blockID: String? = nil, startAtSummary: Bool = false, readyButton: String? = nil,
    refreshCounter: Bool = false
) throws -> XCUIApplication {
    let app = ScreenTestApp.makeApplication()
    app.launchArguments = AuthUIFlow.arguments()
    if let appearance { app.launchArguments += ["-AppleInterfaceStyle", appearance == .dark ? "Dark" : "Light"] }
    if presentLegend { app.launchEnvironment["CF_PLAN_TEST_SHEET"] = "legend" }
    if let stepID { app.launchEnvironment["CF_PLAN_TEST_SHEET"] = "step:\(stepID)" }
    if let route { app.launchEnvironment["CF_PLAN_TEST_ROUTE"] = route }
    if let blockID { app.launchEnvironment["CF_PLAN_TEST_BLOCK"] = blockID }
    if startAtSummary { app.launchEnvironment["CF_PLAN_TEST_POSITION"] = "summary" }
    if freezePlanClock { app.launchEnvironment["CF_PLAN_TEST_FREEZE_CLOCK"] = "1" }
    if emptyTrips { app.launchEnvironment["CF_REFRESH_TEST_EMPTY_TRIPS"] = "1" }
    if refreshCounter { app.launchEnvironment["CF_REFRESH_TEST_COUNTER"] = "1" }
    AuthUIFlow.launchSignedIn(app, walkthroughSeen: true)
    let identifier =
        presentLegend
        ? "legend.sheet"
        : stepID != nil
            ? "step.sheet"
            : route == "trips" ? "trips.screen" : route?.hasPrefix("trip:") == true ? "trip.scroll" : "today.screen"
    let ready = readyButton.map { app.buttons[$0].firstMatch } ?? app.scrollViews[identifier].firstMatch
    let state: XCUIElement.WaitState = readyButton == nil ? .exists : .hittable
    _ = try XCTUnwrap(ready.waitUntil(state, timeout: 5) ? ready : nil, "Expected seeded \(readyButton ?? identifier)")
    return app
}
