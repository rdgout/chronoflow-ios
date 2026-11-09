import XCTest

#if os(iOS)
    @MainActor
    enum UIWait {
        static func stableFrames(_ elements: [XCUIElement], timeout: TimeInterval = 60) throws -> [CGRect] {
            try waitForFrames(elements, timeout: timeout, isReady: { _ in true }, message: "UI frames did not settle")
        }

        static func keyboardFrames(
            in app: XCUIApplication, including elements: [XCUIElement], timeout: TimeInterval = 10
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
            let predicate = NSPredicate { _, _ in
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
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
            let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
            return try XCTUnwrap(settled, "\(message): \(result); frames=\(latest)")
        }
    }
#endif
