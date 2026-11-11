import XCTest

@MainActor enum UITestTiming {
    private static var awaitingFirstElement: [String: String]?

    static func record(_ event: String, environment: [String: String], details: String = "") {
        let id = environment["CF_AUTH_TEST_ID"] ?? "ungated"
        print(
            "CF_UI_TIMELINE id=\(id.lowercased()) side=runner event=\(event) wall=\(Date().timeIntervalSince1970) uptime=\(ProcessInfo.processInfo.systemUptime) \(details)"
        )
    }

    static func awaitFirstElement(environment: [String: String]) { awaitingFirstElement = environment }

    static func firstElementFound() {
        guard let environment = awaitingFirstElement else { return }
        awaitingFirstElement = nil
        record("first-element-found", environment: environment)
    }

    enum Profile: String { case screen, launch }

    static func launch(_ app: XCUIApplication, profile: Profile) {
        if app.launchEnvironment["CF_AUTH_TEST_ID"] == nil {
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        }
        if app.launchEnvironment["CF_UI_TEST_PROFILE"] == nil {
            app.launchEnvironment["CF_UI_TEST_PROFILE"] = profile.rawValue
        }
        if ScreenTestApp.reseedIfPossible(app) { return }
        if profile == .screen, let data = try? JSONEncoder().encode(app.launchArguments) {
            // XCTest adds process arguments; preserve the caller's launch settings for scene-side validation.
            app.launchEnvironment["CF_UI_TEST_LAUNCH_ARGUMENTS"] = String(decoding: data, as: UTF8.self)
        }
        record("launch-begin", environment: app.launchEnvironment)
        app.launch()
        ScreenTestApp.didLaunch(app)
        record("launch-return", environment: app.launchEnvironment)
        awaitingFirstElement = app.launchEnvironment
    }
}

extension XCUIApplication {
    func launchMeasured(profile: UITestTiming.Profile = .screen) { UITestTiming.launch(self, profile: profile) }
}
