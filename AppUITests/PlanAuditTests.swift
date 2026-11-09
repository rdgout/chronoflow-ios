import DesignSystem
import UIKit
import XCTest

nonisolated final class PlanAuditTests: XCTestCase {
    override func setUp() {
        super.setUp()
        executionTimeAllowance = 120
        continueAfterFailure = false
    }

    @MainActor func testTodayPrimaryState() async throws {
        try await audit { app in
            let progress = app.staticTexts["today.progress"]
            XCTAssertTrue(progress.waitForMeasuredExistence(timeout: 8))
            _ = try UIWait.stableFrames(
                [app.scrollViews["today.screen"], progress, app.tabBars.firstMatch], timeout: 8
            )
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "today.progress").count, 1)
            XCTAssertFalse(app.buttons["today.progress"].exists)
        }
    }
    @MainActor func testTripsPrimaryState() async throws {
        try await audit { app in
            app.tabBars.buttons["My trips"].tap()
            XCTAssertTrue(app.scrollViews["trips.screen"].waitForMeasuredExistence(timeout: 6))
        }
    }
    @MainActor func testTripsEmptyState() async throws {
        try await audit(emptyTrips: true) { app in
            app.tabBars.buttons["My trips"].tap()
            XCTAssertTrue(app.otherElements["trips.empty"].waitForExistence(timeout: 6))
            let create = app.buttons["trips.create-empty"]
            XCTAssertTrue(create.exists)
            XCTAssertTrue(create.isHittable)
        }
    }
    @MainActor func testStepSheetPrimaryState() async throws {
        try await audit { app in
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.step.actionable."))
                .firstMatch
            XCTAssertTrue(row.waitForMeasuredExistence(timeout: 12))
            AuthUIFlow.reveal(row, in: app, scroll: app.scrollViews["today.screen"])
            row.tap()
            let sheet = app.scrollViews["step.sheet"]
            XCTAssertTrue(sheet.waitForMeasuredExistence(timeout: 4), app.debugDescription)
            let title = app.staticTexts.matching(NSPredicate(format: "identifier ENDSWITH %@", "|step.title"))
                .firstMatch
            let time = app.staticTexts.matching(NSPredicate(format: "identifier ENDSWITH %@", "|step.time")).firstMatch
            let footer = app.staticTexts.matching(NSPredicate(format: "identifier ENDSWITH %@", "|step.footer"))
                .firstMatch
            // The inset medium sheet scales its content; audit the native, unscaled large reading position.
            _ = try UIWait.stableFrames([sheet, title], timeout: 8)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(
                CGVector(
                    dx: sheet.frame.midX - app.frame.minX, dy: sheet.frame.minY - app.frame.minY + PlanUITokens.space2))
            let end = origin.withOffset(CGVector(dx: app.frame.width / 2, dy: app.frame.height * 0.15))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            _ = try UIWait.stableFrames(
                [sheet, title, time, footer, app.buttons["step.done"], app.buttons["step.skip"]], timeout: 8)
            XCTAssertEqual(sheet.frame.width, app.frame.width, accuracy: 1)
            let traits = UITraitCollection(preferredContentSizeCategory: .large)
            XCTAssertGreaterThanOrEqual(
                title.frame.height, Typography.screenCardTitle.uiFont(compatibleWith: traits).lineHeight - 1)
        }
    }
    @MainActor func testLegendPrimaryState() async throws {
        try await audit(legend: true) { app in
            XCTAssertTrue(app.scrollViews["legend.sheet"].waitForMeasuredExistence(timeout: 4))
        }
    }
    @MainActor private func audit(
        legend: Bool = false, emptyTrips: Bool = false, _ navigate: (XCUIApplication) throws -> Void
    ) async throws {
        try await FontRegistry.register()
        let appearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = appearance }
        try DeviceAppearance.set(.light)
        let app = try launchPlanAccount(presentLegend: legend, freezePlanClock: true, emptyTrips: emptyTrips)
        defer { app.terminate() }
        try navigate(app)
        let scene = AuditScene(app: app)
        _ = try UIWait.stableFrames([scene.content], timeout: 8)
        attach(app, name: "plan-audit-settled")
        // The user settled the root xxLarge cap on 2026-11-06 (plan Phase 5 fix round 3).
        let types: XCUIAccessibilityAuditType = .all.subtracting(.dynamicType)
        XCTAssertEqual(types, .all.subtracting(.dynamicType), "Honor the root xxLarge cap; keep every other audit")
        let sources = scene.content.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "plan.text."))
            .allElementsBoundByIndex.map { TextSource(identifier: $0.identifier, label: $0.label, frame: $0.frame) }
        var findings: [Finding] = []
        // Capture every finding before contrast measurements scroll the original audit scene.
        try UIWait.accessibilityAudit(in: app, types: types, timeout: 45) { issue in
            findings.append(Finding(issue: issue, disabled: Self.disabledControl(issue: issue, in: app)))
            return true
        }
        let measurementDeadline = ContinuousClock.now + .seconds(45)
        for finding in findings {
            guard ContinuousClock.now < measurementDeadline else {
                throw AuditFailure(
                    message: "Plan contrast measurements exceeded 45s; next=\(finding.identifier ?? "<nil>")")
            }
            var measurement = "not eligible"
            var measured = false
            if finding.type == .contrast {
                (measured, measurement) = try measuredText(
                    finding: finding, sources: sources, in: app, scene: scene, deadline: measurementDeadline)
            }
            let ignored = measured || finding.disabled
            let message = """
                Plan accessibility auditType=\(finding.type) \
                identifier=\(finding.identifier ?? "<nil>") label=\(finding.label ?? "<nil>") \
                frame=\(String(describing: finding.frame)) compactDescription=\(finding.description) \
                measuredText=\(measured) disabledControl=\(finding.disabled) ignored=\(ignored)
                \(measurement)
                """
            print(message)
            let attachment = XCTAttachment(string: message)
            attachment.lifetime = .keepAlways
            add(attachment)
            if !ignored { XCTFail(message) }
        }
    }

    private struct AuditFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    @MainActor private struct AuditScene {
        let content: XCUIElement
        let navigation: XCUIElement?
        let tabBar: XCUIElement?

        init(app: XCUIApplication) {
            let legend = app.descendants(matching: .any).matching(identifier: "legend.sheet").firstMatch
            let step = app.descendants(matching: .any).matching(identifier: "step.sheet").firstMatch
            if legend.exists {
                content = legend
                navigation = app.navigationBars["What the steps mean"]
                tabBar = nil
            } else if step.exists {
                content = step
                navigation = nil
                tabBar = nil
            } else {
                content = app.scrollViews.firstMatch
                navigation = app.navigationBars.firstMatch
                tabBar = app.tabBars.firstMatch
            }
        }
    }

    private struct TextSource {
        let identifier: String
        let label: String
        let frame: CGRect
    }

    private struct Finding {
        let type: XCUIAccessibilityAuditType
        let identifier: String?
        let label: String?
        let frame: CGRect?
        let description: String
        let disabled: Bool

        @MainActor init(issue: XCUIAccessibilityAuditIssue, disabled: Bool) {
            type = issue.auditType
            identifier = issue.element?.identifier
            label = issue.element?.label
            frame = issue.element?.frame
            description = issue.compactDescription
            self.disabled = disabled
        }
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func measuredText(
        finding: Finding, sources: [TextSource], in app: XCUIApplication, scene: AuditScene,
        deadline: ContinuousClock.Instant
    ) throws -> (Bool, String) {
        guard let identifier = finding.identifier, let reportedFrame = finding.frame else {
            return (false, "No attributed element")
        }
        if identifier == "legend.close" {
            let close = app.buttons["legend.close"]
            guard close.exists, close.frame == reportedFrame, close.label == finding.label else {
                return (false, "Close control identity/frame mismatch")
            }
            let frame = close.frame
            let (minimum, description) = measure(
                app: app, identifier: close.identifier, label: close.label, frame: frame,
                viewport: app.frame, ink: .label, lineHeight: frame.height)
            return (
                PlanLayoutEvidence.passingText(
                    issueIdentifier: identifier, issueFrame: reportedFrame,
                    identifier: close.identifier, frame: frame, minimum: minimum), description
            )
        }
        let candidates = sources.filter { source in
            PlanLayoutEvidence.attributedText(
                issueIdentifier: identifier, issueFrame: reportedFrame,
                identifier: source.identifier, frame: source.frame)
        }
        guard candidates.count == 1, let source = candidates.first else {
            return (false, "No unique original text identifier and frame; candidates=\(candidates.count)")
        }
        let live = scene.content.staticTexts.matching(identifier: source.identifier).allElementsBoundByIndex
        guard live.count == 1, let text = live.first, text.label == source.label else {
            return (false, "Original text no longer has a unique live identity: \(source.identifier)")
        }
        let originalFrame = source.frame
        let label = source.label
        let styles: [Typography.Style] = [
            Typography.screenHero, Typography.screenPageTitle, Typography.screenPageTitleLg,
            Typography.screenCardTitle, Typography.screenSectionTitle, Typography.screenDayTitle,
            Typography.screenBodyLg, Typography.screenBody, Typography.screenLabel, Typography.screenMeta,
            Typography.screenEyebrow, Typography.screenBlockLabel, Typography.screenPriorityTag,
        ]
        let metadata = text.identifier.components(separatedBy: "|")[0]
        let pairs = ColorToken.allCases.flatMap { color in
            styles.filter { $0.planTextIdentifier(color: color) == metadata }.map { ($0, color) }
        }
        guard pairs.count == 1, let (style, color) = pairs.first else {
            return (false, "Unknown text style: \(text.identifier)")
        }
        let scrolls = [scene.content].filter {
            $0.elementType == .scrollView
                && $0.descendants(matching: .staticText).matching(identifier: text.identifier).allElementsBoundByIndex
                    .contains { $0.frame == text.frame && $0.label == label }
        }
        // System glass can cover scroll content; measure the same text in its unobscured reading position.
        let readingViewport = try reveal(
            text, in: app, scene: scene, scroll: scrolls.first, deadline: deadline)
        guard text.label == label else {
            return (false, "Revealed text changed: expected=\(label), actual=\(text.label)")
        }
        let current = scene.content.staticTexts.matching(identifier: text.identifier).allElementsBoundByIndex
        guard current.count == 1, current[0].label == label, current[0].frame == text.frame else {
            return (false, "Revealed text is not unique: \(text.identifier), original=\(originalFrame)")
        }
        let traits = UITraitCollection {
            $0.userInterfaceStyle = .light
            $0.preferredContentSizeCategory = .large
        }
        let (minimum, description) = measure(
            app: app, identifier: text.identifier, label: label, frame: text.frame,
            viewport: readingViewport, ink: UIColor(color.color).resolvedColor(with: traits),
            lineHeight: style.uiFont(compatibleWith: traits).lineHeight)
        return (
            PlanLayoutEvidence.passingText(
                issueIdentifier: identifier, issueFrame: reportedFrame,
                identifier: text.identifier, frame: originalFrame, minimum: minimum),
            "reportedFrame=\(reportedFrame) originalTextFrame=\(originalFrame)\n" + description
        )
    }

    @MainActor private func viewport(in app: XCUIApplication, scene: AuditScene, clearance: CGFloat) -> CGRect {
        return AuthScrollGesture.readingViewport(
            AuthUIFlow.viewport(in: app, scrollFrame: scene.content.frame),
            navigationBar: scene.navigation.flatMap { $0.exists ? $0.frame : nil },
            tabBar: scene.tabBar.flatMap { $0.exists ? $0.frame : nil }, clearance: clearance)
    }

    @MainActor private func reveal(
        _ text: XCUIElement, in app: XCUIApplication, scene: AuditScene, scroll: XCUIElement?,
        deadline: ContinuousClock.Instant
    ) throws -> CGRect {
        let deadline = min(deadline, ContinuousClock.now + .seconds(15))
        var progress = AuthScrollGesture.TextRevealProgress()
        var diagnostics = ""
        for attempt in 0..<6 {
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { break }
            var elements = [text, scene.content]
            if let tabBar = scene.tabBar, tabBar.exists { elements.append(tabBar) }
            if let navigation = scene.navigation, navigation.exists { elements.append(navigation) }
            do {
                let seconds = Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18
                _ = try UIWait.stableFrames(elements, timeout: min(4, seconds))
            } catch {
                throw AuditFailure(message: "Plan reveal frames did not settle for \(text.identifier): \(error)")
            }
            let visible = viewport(in: app, scene: scene, clearance: 0)
            let preferred = viewport(in: app, scene: scene, clearance: PlanUITokens.space4)
            let frame = text.frame
            diagnostics = "attempt=\(attempt) frame=\(frame) visible=\(visible) preferred=\(preferred)"
            switch progress.observe(frame: frame, visible: visible, preferred: preferred, canScroll: scroll != nil) {
            case .measure(let viewport): return viewport
            case .blocked:
                throw AuditFailure(
                    message: "Plan text remains clipped at its scroll limit: \(text.identifier); \(diagnostics)")
            case .scroll: break
            }
            guard ContinuousClock.now < deadline,
                let gesture = AuthScrollGesture.reveal(frame, in: preferred)
            else { break }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(
                CGVector(dx: gesture.start.x - app.frame.minX, dy: gesture.start.y - app.frame.minY))
            let end = origin.withOffset(
                CGVector(dx: gesture.end.x - app.frame.minX, dy: gesture.end.y - app.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        throw AuditFailure(message: "Plan text reveal exceeded 15s or 6 gestures: \(text.identifier); \(diagnostics)")
    }

    @MainActor private func measure(
        app: XCUIApplication, identifier: String, label: String, frame: CGRect,
        viewport: CGRect, ink: UIColor, lineHeight: CGFloat
    ) -> (Double?, String) {
        guard viewport.contains(frame) else { return (nil, "Text is clipped: \(frame), viewport=\(viewport)") }
        let traits = UITraitCollection(userInterfaceStyle: .light)
        guard
            let rgb = ink.resolvedColor(with: traits).cgColor.converted(
                to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric, options: nil)?.components
        else { return (nil, "Cannot resolve ink for \(identifier)") }
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(identifier) contrast source"
        attachment.lifetime = .keepAlways
        add(attachment)
        let appFrame = app.frame
        let localFrame = frame.offsetBy(dx: -appFrame.minX, dy: -appFrame.minY)
        let localViewport = viewport.offsetBy(dx: -appFrame.minX, dy: -appFrame.minY)
        do {
            let raster = try SnapshotRaster(png: screenshot.pngRepresentation)
            let scale = CGFloat(raster.width) / appFrame.width
            guard scale.isFinite, scale > 0, abs(CGFloat(raster.height) / scale - appFrame.height) < 1 else {
                return (nil, "Screenshot and app bounds disagree: \(raster.width)×\(raster.height), app=\(appFrame)")
            }
            let result = RenderedTextContrast.measure(
                raster: raster, frame: localFrame, scale: scale, lineHeight: lineHeight,
                text: Array(rgb.prefix(3)).map(Double.init), viewport: localViewport)
            let message = """
                text identifier=\(identifier) label=\(label) frame=\(frame) viewport=\(viewport) \
                minimum=\(String(describing: result.minimum)) lines=\(result.lines.count)/\(result.expectedLines)
                \(result.lines.map { "frame=\($0.frame) minimum=\($0.minimum):1 ink=\($0.ink)" }.joined(separator: "\n"))
                """
            return (result.minimum, message)
        } catch { return (nil, "\(identifier) measurement failed: \(error)") }
    }

    @MainActor private static func disabledControl(
        issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication
    ) -> Bool {
        guard issue.auditType == .contrast || issue.auditType == .hitRegion,
            let element = issue.element, !element.identifier.isEmpty,
            element.elementType == .button || element.elementType == .switch,
            !element.isEnabled, !element.frame.isEmpty, !element.frame.isInfinite
        else { return false }
        let matches = app.descendants(matching: element.elementType).matching(identifier: element.identifier)
            .allElementsBoundByIndex.filter { $0.frame == element.frame && $0.label == element.label && !$0.isEnabled }
        return matches.count == 1
    }
}
