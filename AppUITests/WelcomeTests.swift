import XCTest

nonisolated final class WelcomeTests: XCTestCase {
    @MainActor
    func testEnglishWelcomeAccessibilityInBothAppearances() async throws {
        try await assertAccessibility(language: "en")
    }

    @MainActor
    func testDutchWelcomeAccessibilityInBothAppearances() async throws {
        try await assertAccessibility(language: "nl")
    }

    @MainActor
    func testDutchAX5TextCanScrollToBothActions() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-cf.session", "out", "-cf.reduceMotion", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["welcome.wordmark"].waitForExistence(timeout: 6))
        XCTAssertEqual(
            app.staticTexts["welcome.headline"].label,
            "Plan de verschuiving van je biologische klok voor je volgende reis")
        Self.scrollTo(app.buttons["welcome.signIn"], in: app)
        for (identifier, label) in [("welcome.plan", "Plan mijn reis"), ("welcome.signIn", "Inloggen")] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(Self.isFullyVisible(button.frame, in: app.windows.firstMatch.frame))
            XCTAssertEqual(button.label, label)
            XCTAssertGreaterThanOrEqual(button.frame.height, 52)
        }
    }

    @MainActor
    func testAX5WelcomeMatchesXXLargeAndEyebrowDoesNotClip() async throws {
        for language in ["en", "nl"] {
            var reference: [CGRect] = []
            for category in ["UICTContentSizeCategoryXXL", "UICTContentSizeCategoryAccessibilityXXXL"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-cf.session", "out", "-cf.reduceMotion", "-AppleLanguages", "(\(language))",
                    "-UIPreferredContentSizeCategoryName", category,
                ]
                app.launch()
                defer { app.terminate() }
                XCTAssertTrue(app.staticTexts["welcome.eyebrow"].waitForExistence(timeout: 10))
                let frames = ["welcome.wordmark", "welcome.eyebrow", "welcome.headline"].map {
                    app.staticTexts[$0].frame
                }
                if reference.isEmpty { reference = frames } else { XCTAssertEqual(frames, reference) }
                try auditTopAndActions(
                    app, language: language, appearance: XCUIDevice.shared.appearance, types: .textClipped)
            }
        }
    }

    @MainActor
    fileprivate static func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable && Self.isFullyVisible(element.frame, in: app.windows.firstMatch.frame) { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(
            Self.isFullyVisible(element.frame, in: app.windows.firstMatch.frame),
            "\(element.identifier) frame \(element.frame) must be fully inside \(app.windows.firstMatch.frame)")
    }

    @MainActor
    private func assertAccessibility(language: String) async throws {
        let device = XCUIDevice.shared
        let previousAppearance = device.appearance
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in
            app.terminate()
            device.appearance = previousAppearance
            let restored = try await LaunchSceneTests.waitForAppearance(previousAppearance)
            XCTAssertTrue(restored)
        }
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            app.terminate()
            device.appearance = appearance
            device.press(.home)
            XCTAssertTrue(
                XCUIApplication(bundleIdentifier: "com.apple.springboard").wait(for: .runningForeground, timeout: 10))
            let applied = try await LaunchSceneTests.waitForAppearance(appearance)
            XCTAssertTrue(applied)
            app.launchArguments = [
                "-cf.session", "out", "-cf.reduceMotion", "-AppleLanguages", "(\(language))",
                "-AppleLocale", language == "nl" ? "nl_NL" : "en_US",
            ]
            app.launch()
            XCTAssertTrue(app.staticTexts["welcome.wordmark"].waitForExistence(timeout: 6))
            let wordmark = app.staticTexts["welcome.wordmark"]
            let eyebrow = app.staticTexts["welcome.eyebrow"]
            let headline = app.staticTexts["welcome.headline"]
            XCTAssertEqual(wordmark.label, "ChronoFlow")
            XCTAssertEqual(eyebrow.label, language == "nl" ? "JETLAGPLANNER" : "JET-LAG PLANNER")
            XCTAssertLessThan(wordmark.frame.maxY, eyebrow.frame.minY)
            XCTAssertLessThan(eyebrow.frame.maxY, headline.frame.minY)
            try auditTopAndActions(app, language: language, appearance: appearance)
        }
    }

    @MainActor
    private func auditTopAndActions(
        _ app: XCUIApplication, language: String, appearance: XCUIDevice.Appearance,
        types: XCUIAccessibilityAuditType = WelcomeTests.welcomeAuditTypes
    ) throws {
        try audit(app, language: language, appearance: appearance, types: types)
        Self.scrollTo(app.buttons["welcome.signIn"], in: app)
        for identifier in ["welcome.plan", "welcome.signIn"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(
                Self.isFullyVisible(button.frame, in: app.windows.firstMatch.frame),
                "\(identifier) frame \(button.frame) must be fully inside \(app.windows.firstMatch.frame) for the audit"
            )
        }
        try audit(app, language: language, appearance: appearance, types: types)
    }

    @MainActor
    fileprivate static func isFullyVisible(_ frame: CGRect, in window: CGRect) -> Bool {
        !frame.isEmpty && window.contains(frame)
    }

    @MainActor
    fileprivate static var welcomeAuditTypes: XCUIAccessibilityAuditType { .all.subtracting(.dynamicType) }

    @MainActor
    private func audit(
        _ app: XCUIApplication, language: String, appearance: XCUIDevice.Appearance,
        types: XCUIAccessibilityAuditType = WelcomeTests.welcomeAuditTypes
    ) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element
            let identifier = element?.identifier
            let label = element?.label
            let frame = element?.frame
            let window = app.windows.firstMatch.frame
            let boardContrast = Self.isBoardContrast(identifier: identifier, auditType: issue.auditType)
            let partiallyVisible = frame.map { !Self.isFullyVisible($0, in: window) } ?? false
            let ignored = Self.shouldIgnoreAuditIssue(
                identifier: identifier, auditType: issue.auditType, elementFrame: frame, window: window)
            let message = """
                Welcome accessibility [\(language), \(appearance)] \
                auditType=\(issue.auditType) identifier=\(identifier ?? "<nil>") \
                label=\(label ?? "<nil>") compactDescription=\(issue.compactDescription) \
                boardContrast=\(boardContrast) partiallyVisible=\(partiallyVisible) ignored=\(ignored)
                """
            print(message)
            let attachment = XCTAttachment(string: message)
            attachment.lifetime = .keepAlways
            self.add(attachment)
            return ignored
        }
    }

    @MainActor
    fileprivate static func shouldIgnoreAuditIssue(
        identifier: String?, auditType: XCUIAccessibilityAuditType, elementFrame: CGRect?, window: CGRect
    ) -> Bool {
        guard auditType == .contrast, let elementFrame else { return false }
        return isBoardContrast(identifier: identifier, auditType: auditType)
            || !isFullyVisible(elementFrame, in: window)
    }

    @MainActor
    fileprivate static func isBoardContrast(identifier: String?, auditType: XCUIAccessibilityAuditType) -> Bool {
        guard auditType == .contrast else { return false }
        switch identifier {
        case "welcome.eyebrow", "welcome.headline", "welcome.copy", "welcome.plan", "welcome.signIn":
            return true
        default:
            return false
        }
    }

    @MainActor
    func testFrozenMoonLandsOnTheMeasuredWelcomeMoon() throws {
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-cf.mode", "welcome", "-cf.freezeAt", "2300",
                "-UIPreferredContentSizeCategoryName", category,
            ]
            app.launch()
            defer { app.terminate() }
            let opening = app.images["launch.opening"]
            XCTAssertTrue(opening.waitForExistence(timeout: 10))
            let hasMeasurement = NSPredicate { element, _ in
                (element as? XCUIElement)?.value is String
            }
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [XCTNSPredicateExpectation(predicate: hasMeasurement, object: opening)], timeout: 10),
                .completed)
            let value = try XCTUnwrap(opening.value as? String)
            let measurement = try JSONDecoder().decode([String: [Double]].self, from: Data(value.utf8))
            let target = try XCTUnwrap(measurement["target"])
            let moon = try XCTUnwrap(measurement["moon"])
            XCTAssertEqual(moon[0], target[0], accuracy: 0.5)
            XCTAssertEqual(moon[1], target[1], accuracy: 0.5)
            XCTAssertEqual(moon[2] * 104, target[2], accuracy: 0.5)
        }
    }
}

nonisolated final class WelcomeLogicTests: XCTestCase {
    @MainActor
    func testPlanMyTripOpensTheGuestWizard() {
        assertRoute(button: "welcome.plan", route: "guestWizard")
    }

    @MainActor
    func testSignInOpensSignIn() {
        assertRoute(button: "welcome.signIn", route: "signIn")
    }

    @MainActor
    private func assertRoute(button identifier: String, route: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-cf.session", "out"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["welcome.wordmark"].waitForExistence(timeout: 6))
        let button = app.buttons[identifier]
        for _ in 0..<8 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue(app.staticTexts["route.\(route)"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAuditVisibilityRejectsPartiallyVisibleAndEmptyActions() {
        let window = CGRect(x: 0, y: 0, width: 466, height: 678)
        let button = CGRect(x: 24, y: 600, width: 418, height: 52)
        XCTAssertTrue(WelcomeTests.isFullyVisible(button, in: window))
        for frame in [
            button.offsetBy(dx: 0, dy: 27), button.offsetBy(dx: 0, dy: -601),
            button.offsetBy(dx: -25, dy: 0), button.offsetBy(dx: 25, dy: 0),
            CGRect.zero, .null, .infinite,
        ] {
            XCTAssertFalse(WelcomeTests.isFullyVisible(frame, in: window))
        }
    }

    @MainActor
    func testAuditTypesRespectTheUserDynamicTypeCap() {
        XCTAssertEqual(
            WelcomeTests.welcomeAuditTypes, XCUIAccessibilityAuditType.all.subtracting(.dynamicType),
            "User decision 2026-11-06: cap Dynamic Type at xxLarge; audit every other accessibility type")
        XCTAssertFalse(
            WelcomeTests.welcomeAuditTypes.contains(.dynamicType),
            "User decision 2026-11-06: xxLarge is the maximum supported Dynamic Type size")
    }

    @MainActor
    func testAuditIgnoresOnlyContrastOnElementsOutsideTheWindowOrBoardPairs() {
        let window = CGRect(x: 0, y: 0, width: 375, height: 667)
        let visible = CGRect(x: 24, y: 590, width: 327, height: 52)
        let partial = visible.offsetBy(dx: 0, dy: 26)
        XCTAssertTrue(
            WelcomeTests.shouldIgnoreAuditIssue(
                identifier: "welcome.plan", auditType: .contrast, elementFrame: partial, window: window))
        for identifier in ["welcome.wordmark", "welcome.newElement"] {
            XCTAssertTrue(
                WelcomeTests.shouldIgnoreAuditIssue(
                    identifier: identifier, auditType: .contrast, elementFrame: partial, window: window))
            XCTAssertFalse(
                WelcomeTests.shouldIgnoreAuditIssue(
                    identifier: identifier, auditType: .contrast, elementFrame: visible, window: window))
        }
        for type: XCUIAccessibilityAuditType in [.textClipped, .dynamicType, .hitRegion, .trait, .all] {
            XCTAssertFalse(
                WelcomeTests.shouldIgnoreAuditIssue(
                    identifier: "welcome.plan", auditType: type, elementFrame: partial, window: window))
        }
        XCTAssertFalse(
            WelcomeTests.shouldIgnoreAuditIssue(
                identifier: "welcome.plan", auditType: [.contrast, .textClipped], elementFrame: partial, window: window)
        )
        XCTAssertFalse(
            WelcomeTests.shouldIgnoreAuditIssue(
                identifier: nil, auditType: .contrast, elementFrame: nil, window: window))
        for identifier in ["welcome.eyebrow", "welcome.headline", "welcome.copy", "welcome.plan", "welcome.signIn"] {
            XCTAssertTrue(
                WelcomeTests.shouldIgnoreAuditIssue(
                    identifier: identifier, auditType: .contrast, elementFrame: visible, window: window))
            XCTAssertFalse(
                WelcomeTests.shouldIgnoreAuditIssue(
                    identifier: identifier, auditType: .textClipped, elementFrame: partial, window: window))
            XCTAssertFalse(
                WelcomeTests.shouldIgnoreAuditIssue(
                    identifier: identifier, auditType: .contrast, elementFrame: nil, window: window))
        }
    }

    @MainActor
    func testAuditExceptionsAreLimitedToExplicitBoardContrastPairs() {
        for identifier in [
            "welcome.eyebrow", "welcome.headline", "welcome.copy", "welcome.plan", "welcome.signIn",
        ] {
            XCTAssertTrue(WelcomeTests.isBoardContrast(identifier: identifier, auditType: .contrast))
            for type: XCUIAccessibilityAuditType in [.textClipped, .dynamicType, .hitRegion, .trait, .all] {
                XCTAssertFalse(WelcomeTests.isBoardContrast(identifier: identifier, auditType: type))
            }
            XCTAssertFalse(WelcomeTests.isBoardContrast(identifier: identifier, auditType: [.contrast, .textClipped]))
        }
        for identifier in [
            nil, "", "welcome", "welcome.wordmark", "welcome.newElement", "route.signIn",
        ] {
            XCTAssertFalse(WelcomeTests.isBoardContrast(identifier: identifier, auditType: .contrast))
        }
    }
}
