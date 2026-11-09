import XCTest

@MainActor enum UIReseed {
    static func apply(to app: XCUIApplication, authorization: String, timeout: TimeInterval = 12) throws {
        let command = UITestSeedCommand(
            authorization: authorization, environment: app.launchEnvironment, arguments: app.launchArguments)
        UITestTiming.record("reset-begin", environment: app.launchEnvironment)
        UITestTiming.awaitFirstElement(environment: app.launchEnvironment)
        app.open(try command.url())
        let ready = app.windows["uitest.ready.\(command.nonce)"].firstMatch
        let failed = app.windows["uitest.failed.\(command.nonce)"].firstMatch
        let acknowledged = UIWait.until(timeout: timeout) { ready.exists || failed.exists }
        guard acknowledged, ready.exists else {
            XCTFail("In-app reseed did not mount a fresh root (nonce=\(command.nonce), failed=\(failed.exists))")
            throw NSError(domain: "UIReseed", code: 1)
        }
        UITestTiming.record("reset-return", environment: app.launchEnvironment)
    }
}
