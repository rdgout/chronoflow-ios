import XCTest

nonisolated class ScreenTestCase: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 60
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
    private static var launchedSeed: UITestSeedCommand?
    private static var authorization: String?
    private(set) static var coldLaunches = 0
    private(set) static var reseeds = 0

    static func beginClass(_ name: String) {
        guard owner != name else { return }
        application?.terminate()
        application = nil
        launchedSeed = nil
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
        application?.terminate()
        application = nil
        launchedSeed = nil
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
        let comparison = UITestSeedCommand(
            authorization: "", environment: app.launchEnvironment, arguments: app.launchArguments)
        if app.state == .runningForeground, let authorization, let launchedSeed {
            let changed = comparison.changedLaunchSettings(
                arguments: launchedSeed.arguments, environment: launchedSeed.environment)
            if changed.isEmpty {
                do {
                    try UIReseed.apply(to: app, authorization: authorization)
                    reseeds += 1
                } catch {
                    app.terminate()
                }
                return true
            }
            UITestTiming.record(
                "cold-launch-required", environment: app.launchEnvironment,
                details: "changed=\(changed.joined(separator: ","))")
        }
        if app.state != .notRunning { app.terminate() }
        return false
    }

    static func didLaunch(_ app: XCUIApplication) {
        UIReseed.didLaunch(app)
        guard application === app else { return }
        authorization = app.launchEnvironment["CF_AUTH_TEST_ID"]
        launchedSeed = UITestSeedCommand(
            authorization: "", environment: app.launchEnvironment, arguments: app.launchArguments)
        coldLaunches += 1
    }
}
