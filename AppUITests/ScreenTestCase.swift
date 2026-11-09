import XCTest

nonisolated class ScreenTestCase: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = ProcessInfo.processInfo.environment["AUTH_AUDIT_FULL"] == "1" ? 600 : 120
        let name = String(reflecting: type(of: self))
        await ScreenTestApp.beginClass(name)
    }

    override class func tearDown() {
        ScreenTestApp.finishClass()
        super.tearDown()
    }
}

@MainActor enum ScreenTestApp {
    private static var owner: String?
    private static var application: XCUIApplication?
    private static var launchedArguments: [String]?
    private static var authorization: String?
    private(set) static var coldLaunches = 0
    private(set) static var reseeds = 0

    static func beginClass(_ name: String) {
        guard owner != name else { return }
        application?.terminate()
        application = nil
        launchedArguments = nil
        authorization = nil
        owner = name
        coldLaunches = 0
        reseeds = 0
    }

    nonisolated static func finishClass() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { finish() }
        } else {
            DispatchQueue.main.sync { finish() }
        }
    }

    private static func finish() {
        if let app = application, app.state == .runningForeground, let authorization {
            app.launchEnvironment = ["CF_AUTH_TEST_ID": UUID().uuidString, "CF_UI_TEST_PROFILE": "screen"]
            try? UIReseed.apply(to: app, authorization: authorization)
        }
        application?.terminate()
        application = nil
        launchedArguments = nil
        authorization = nil
        owner = nil
    }

    static func makeApplication() -> XCUIApplication {
        guard owner != nil else { return XCUIApplication() }
        let app = application ?? XCUIApplication()
        application = app
        app.launchArguments = []
        app.launchEnvironment = [:]
        return app
    }

    static func reseedIfPossible(_ app: XCUIApplication) -> Bool {
        guard application === app, app.launchEnvironment["CF_UI_TEST_PROFILE"] == "screen" else { return false }
        let comparison = UITestSeedCommand(authorization: "", environment: [:], arguments: app.launchArguments)
        if app.state == .runningForeground, let authorization, let launchedArguments,
            comparison.preservesLaunchSettings(in: launchedArguments)
        {
            do {
                try UIReseed.apply(to: app, authorization: authorization)
                reseeds += 1
            } catch {
                app.terminate()
            }
            return true
        }
        if app.state != .notRunning { app.terminate() }
        return false
    }

    static func didLaunch(_ app: XCUIApplication) {
        guard application === app else { return }
        authorization = app.launchEnvironment["CF_AUTH_TEST_ID"]
        launchedArguments = app.launchArguments
        coldLaunches += 1
    }
}
