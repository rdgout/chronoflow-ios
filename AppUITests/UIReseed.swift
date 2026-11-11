import XCTest

@MainActor enum UIReseed {
    static func apply(to app: XCUIApplication, authorization: String, timeout: TimeInterval = 12) throws {
        let command = UITestSeedCommand(
            authorization: authorization, environment: app.launchEnvironment.filter { $0.key.hasPrefix("CF_") },
            arguments: app.launchArguments)
        UITestTiming.record("reset-begin", environment: app.launchEnvironment, details: "nonce=\(command.nonce)")
        UITestTiming.awaitFirstElement(environment: app.launchEnvironment)
        let previous = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH %@", "uitest.ready."))
            .firstMatch
        let process = previous.exists ? previous.label : "missing-ready-window"
        // XCUIApplication.open launches; system.open delivers to the existing scene.
        XCUIDevice.shared.system.open(try command.url())
        let ready = app.windows["uitest.ready.\(command.nonce)"].firstMatch
        let failed = app.windows["uitest.failed.\(command.nonce)"].firstMatch
        let acknowledged = UIWait.until(timeout: timeout, recordsFirstElement: false) { ready.exists || failed.exists }
        guard acknowledged, ready.exists, ready.label == process, process.hasPrefix("uitest.process.") else {
            UITestTiming.record("reset-failed", environment: app.launchEnvironment)
            XCTContext.runActivity(named: "Reseed acknowledgement failure \(command.nonce)") { activity in
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.lifetime = .keepAlways
                activity.add(screenshot)
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Application hierarchy"
                hierarchy.lifetime = .keepAlways
                activity.add(hierarchy)
            }
            XCTFail(
                "In-app reseed did not mount a fresh root in \(process) (nonce=\(command.nonce), state=\(app.state.rawValue), failed=\(failed.exists))"
            )
            throw NSError(domain: "UIReseed", code: 1)
        }
        UITestTiming.record("reset-return", environment: app.launchEnvironment, details: "nonce=\(command.nonce)")
    }
}
