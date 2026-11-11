import DesignSystem
import UIKit
import XCTest

nonisolated final class PlanAuditTests: ScreenTestCase {
    nonisolated(unsafe) private static var fontRegistration: Task<Void, Error>?

    override class func setUp() {
        super.setUp()
        fontRegistration = Task { try await FontRegistry.register() }
    }

    override func setUp() async throws {
        try await super.setUp()
        try await Self.fontRegistration?.value
    }

    @MainActor func testTodayPrimaryState() async throws {
        try await audit(contentIdentifier: "today.screen") { app in
            XCTAssertTrue(app.staticTexts["today.progress"].waitUntil(.exists, timeout: 4))
        }
    }

    @MainActor func testTripsPrimaryState() async throws {
        try await audit(contentIdentifier: "trips.screen", route: "trips") { app in
            XCTAssertTrue(app.buttons["trip.\(PlanUIFlow.tripID)"].waitUntil(.exists, timeout: 4))
        }
    }

    @MainActor func testTripsEmptyState() async throws {
        try await audit(contentIdentifier: "trips.screen", route: "trips", emptyTrips: true) { app in
            XCTAssertTrue(app.otherElements["trips.empty"].waitUntil(.exists, timeout: 4))
            XCTAssertTrue(app.buttons["trips.create-empty"].isHittable)
        }
    }

    @MainActor func testStepSheetPrimaryState() async throws {
        try await audit(contentIdentifier: "step.sheet", stepID: PlanUIFlow.stepID)
    }

    @MainActor func testLegendPrimaryState() async throws {
        try await audit(contentIdentifier: "legend.sheet", legend: true)
    }

    @MainActor private func audit(
        contentIdentifier: String, route: String? = nil, stepID: String? = nil,
        legend: Bool = false, emptyTrips: Bool = false, _ check: (XCUIApplication) throws -> Void = { _ in }
    ) async throws {
        let app = try launchPlanAccount(
            presentLegend: legend, freezePlanClock: true, emptyTrips: emptyTrips, appearance: .light,
            route: route, stepID: stepID)
        try check(app)
        let scene = AuditScene(app: app, contentIdentifier: contentIdentifier)
        _ = try UIWait.stableFrames([scene.content], timeout: 5)
        // The root xxLarge cap excludes dynamicType; all other audit types remain required.
        let types: XCUIAccessibilityAuditType = .all.subtracting(.dynamicType)
        var findings: [Finding] = []
        // Capture only reported text before contrast measurements scroll the audit scene.
        try UIWait.accessibilityAudit(in: app, types: types, timeout: 20) { issue in
            findings.append(Finding(issue: issue, scene: scene))
            return true
        }
        let measurementDeadline = ContinuousClock.now + .seconds(20)
        for finding in findings {
            guard ContinuousClock.now < measurementDeadline else {
                throw AuditFailure(
                    message: "Plan contrast measurements exceeded 20s; next=\(finding.identifier ?? "<nil>")")
            }
            var measurement = "not eligible"
            var measured = false
            if finding.type == .contrast {
                (measured, measurement) = try measuredText(
                    finding: finding, in: app, scene: scene, deadline: measurementDeadline)
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

        init(app: XCUIApplication, contentIdentifier: String) {
            content = app.scrollViews[contentIdentifier].firstMatch
            navigation =
                contentIdentifier == "legend.sheet"
                ? app.navigationBars["What the steps mean"]
                : contentIdentifier == "step.sheet" ? nil : app.navigationBars.firstMatch
            tabBar = ["legend.sheet", "step.sheet"].contains(contentIdentifier) ? nil : app.tabBars.firstMatch
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
        let source: TextSource?

        @MainActor init(issue: XCUIAccessibilityAuditIssue, scene: AuditScene) {
            type = issue.auditType
            identifier = issue.element?.identifier
            label = issue.element?.label
            frame = issue.element?.frame
            description = issue.compactDescription
            disabled = PlanAuditTests.disabledControl(issue: issue)
            if type == .contrast, let identifier {
                let matches = scene.content.staticTexts.matching(identifier: identifier)
                let text = matches.firstMatch
                source =
                    matches.count == 1
                    ? TextSource(identifier: identifier, label: text.label, frame: text.frame) : nil
            } else {
                source = nil
            }
        }
    }

    @MainActor private func measuredText(
        finding: Finding, in app: XCUIApplication, scene: AuditScene,
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
        guard let source = finding.source,
            PlanLayoutEvidence.attributedText(
                issueIdentifier: identifier, issueFrame: reportedFrame,
                identifier: source.identifier, frame: source.frame)
        else { return (false, "No unique original text identifier and frame") }
        let live = scene.content.staticTexts.matching(identifier: source.identifier)
        let text = live.firstMatch
        guard live.count == 1, text.label == source.label else {
            return (false, "Original text no longer has a unique live identity: \(source.identifier)")
        }
        let originalFrame = source.frame
        let label = source.label
        let styles: [Typography.Style] = [
            Typography.screenHero, Typography.screenPageTitle,
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
        // System glass can cover scroll content; measure it in an unobscured reading position.
        let readingViewport = try reveal(
            text, in: app, scene: scene, scroll: scene.content, deadline: deadline)
        guard text.label == label else {
            return (false, "Revealed text changed: expected=\(label), actual=\(text.label)")
        }
        let current = scene.content.staticTexts.matching(identifier: text.identifier)
        guard current.count == 1, current.firstMatch.label == label, current.firstMatch.frame == text.frame else {
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
            let preferred = AuthScrollGesture.readingViewport(
                visible, navigationBar: nil, tabBar: nil, clearance: PlanUITokens.space4)
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
        issue: XCUIAccessibilityAuditIssue
    ) -> Bool {
        guard issue.auditType == .contrast || issue.auditType == .hitRegion,
            let element = issue.element, !element.identifier.isEmpty,
            element.elementType == .button || element.elementType == .switch,
            !element.isEnabled, !element.frame.isEmpty, !element.frame.isInfinite
        else { return false }
        return true
    }
}
