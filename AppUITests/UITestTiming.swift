import XCTest

@MainActor enum UITestTiming {
    private static var awaitingFirstElement: [String: String]?

    static func record(_ event: String, environment: [String: String]) {
        let id = environment["CF_AUTH_TEST_ID"] ?? "ungated"
        print(
            "CF_UI_TIMELINE id=\(id.lowercased()) side=runner event=\(event) wall=\(Date().timeIntervalSince1970) uptime=\(ProcessInfo.processInfo.systemUptime)"
        )
    }

    static func firstElementFound() {
        guard let environment = awaitingFirstElement else { return }
        awaitingFirstElement = nil
        record("first-element-found", environment: environment)
    }

    static func launch(_ app: XCUIApplication) {
        record("launch-begin", environment: app.launchEnvironment)
        app.launch()
        record("launch-return", environment: app.launchEnvironment)
        awaitingFirstElement = app.launchEnvironment
    }
}

extension XCUIApplication {
    func launchMeasured() { UITestTiming.launch(self) }
}
