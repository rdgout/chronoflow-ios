import XCTest

#if os(iOS)
    @MainActor
    enum UIWait {
        static func until(timeout: TimeInterval, recordsFirstElement: Bool = true, condition: () -> Bool) -> Bool {
            let found = BackoffPoll.until(timeout: timeout, condition: condition)
            if found, recordsFirstElement { UITestTiming.firstElementFound() }
            return found
        }

        static func accessibilityAudit(
            in app: XCUIApplication, types: XCUIAccessibilityAuditType, timeout: TimeInterval,
            handler: @escaping (XCUIAccessibilityAuditIssue) throws -> Bool
        ) throws {
            let deadline = AuditDeadline()
            let message = "Native Plan accessibility audit exceeded \(timeout)s; terminated the app to unblock XCTest"
            // XCTest's synchronous audit pumps the run loop and has no cancellation/timeout argument.
            let timer = Timer(timeInterval: timeout, repeats: false) { _ in
                MainActor.assumeIsolated {
                    deadline.expired = true
                    print(message)
                    app.terminate()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            defer { timer.invalidate() }
            try XCTContext.runActivity(named: "Native Plan accessibility audit (\(timeout)s deadline)") { _ in
                do {
                    try app.performAccessibilityAudit(for: types, handler)
                } catch {
                    if deadline.expired { throw timeoutError(message) }
                    throw error
                }
                if deadline.expired { throw timeoutError(message) }
            }
        }

        private final class AuditDeadline {
            var expired = false
        }

        private static func timeoutError(_ message: String) -> NSError {
            NSError(domain: "UIWait", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        static func stableFrames(_ elements: [XCUIElement], timeout: TimeInterval = 5) throws -> [CGRect] {
            try waitForFrames(elements, timeout: timeout, isReady: { _ in true }, message: "UI frames did not settle")
        }

        static func keyboardFrames(
            in app: XCUIApplication, including elements: [XCUIElement], timeout: TimeInterval = 5
        ) throws -> [CGRect] {
            try waitForFrames(
                [app.windows.firstMatch, app.keyboards.firstMatch] + elements, timeout: timeout,
                isReady: { SoftwareKeyboardVisibility.isVisible($0[1], in: $0[0]) },
                message: "software keyboard not visible — check AutomaticMinimizationEnabled")
        }

        private static func waitForFrames(
            _ elements: [XCUIElement], timeout: TimeInterval, isReady: @escaping ([CGRect]) -> Bool, message: String
        ) throws -> [CGRect] {
            var stability = FrameStability()
            var settled: [CGRect]?
            var latest: [CGRect] = []
            let ready = { () -> Bool in
                guard elements.allSatisfy({ $0.exists }) else {
                    _ = stability.observe(nil)
                    return false
                }
                let frames = elements.map(\.frame)
                latest = frames
                guard isReady(frames) else {
                    _ = stability.observe(nil)
                    return false
                }
                if stability.observe(frames) {
                    settled = frames
                    return true
                }
                return false
            }
            let result = until(timeout: timeout, condition: ready)
            return try XCTUnwrap(settled, "\(message): \(result); frames=\(latest)")
        }
    }
#endif

@MainActor extension XCUIElement {
    enum WaitState { case exists, hittable, enabled, gone }

    func waitUntil(_ state: WaitState, timeout: TimeInterval) -> Bool {
        let found = UIWait.until(timeout: timeout, recordsFirstElement: state != .gone) {
            switch state {
            case .exists: self.exists
            case .hittable: self.exists && self.isHittable
            case .enabled: self.exists && self.isEnabled
            case .gone: !self.exists
            }
        }
        if found, state != .gone { UITestTiming.firstElementFound() }
        return found
    }
}
