import DesignSystem
import UIKit
import XCTest

nonisolated final class PlanAuditTests: XCTestCase {
    @MainActor func testTodayPrimaryState() async throws { try await audit { _ in } }
    @MainActor func testTripsPrimaryState() async throws {
        try await audit { app in
            app.tabBars.buttons["My trips"].tap()
            XCTAssertTrue(app.scrollViews["trips.screen"].waitForExistence(timeout: 6))
        }
    }
    @MainActor func testStepSheetPrimaryState() async throws {
        try await audit { app in
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.step.actionable."))
                .firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 12))
            AuthUIFlow.reveal(row, in: app, scroll: app.scrollViews["today.screen"])
            row.tap()
            XCTAssertTrue(app.scrollViews["step.sheet"].waitForExistence(timeout: 4), app.debugDescription)
        }
    }
    @MainActor func testLegendPrimaryState() async throws {
        try await audit(legend: true) { app in
            XCTAssertTrue(app.scrollViews["legend.sheet"].waitForExistence(timeout: 4))
        }
    }
    @MainActor private func audit(legend: Bool = false, _ navigate: (XCUIApplication) -> Void) async throws {
        try await FontRegistry.register()
        let appearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = appearance }
        try DeviceAppearance.set(.light)
        let app = launchPlanAccount(presentLegend: legend)
        defer { app.terminate() }
        navigate(app)
        // The user settled the root xxLarge cap on 2026-11-06 (plan Phase 5 fix round 3).
        let types: XCUIAccessibilityAuditType = .all.subtracting(.dynamicType)
        XCTAssertEqual(types, .all.subtracting(.dynamicType), "Honor the root xxLarge cap; keep every other audit")
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element
            let reportedFrame = element?.frame
            var measurement = "not eligible"
            var measured = false
            if issue.auditType == .contrast {
                (measured, measurement) = self.measuredText(issue: issue, in: app)
            }
            let disabled = Self.disabledControl(issue: issue, in: app)
            let ignored = measured || disabled
            let message = """
                Plan accessibility auditType=\(issue.auditType) \
                identifier=\(element?.identifier ?? "<nil>") label=\(element?.label ?? "<nil>") \
                frame=\(String(describing: reportedFrame)) compactDescription=\(issue.compactDescription) \
                measuredText=\(measured) disabledControl=\(disabled) ignored=\(ignored)
                \(measurement)
                """
            print(message)
            let attachment = XCTAttachment(string: message)
            attachment.lifetime = .keepAlways
            self.add(attachment)
            if !ignored { XCTFail(message) }
            return ignored
        }
    }

    @MainActor private func measuredText(
        issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication
    ) -> (Bool, String) {
        guard let element = issue.element else { return (false, "No attributed element") }
        if element.identifier == "legend.close" {
            let close = app.buttons["legend.close"]
            guard close.exists, close.frame == element.frame, close.label == element.label else {
                return (false, "Close control identity/frame mismatch")
            }
            let frame = close.frame
            let (minimum, description) = measure(
                app: app, identifier: close.identifier, label: close.label, frame: frame,
                viewport: app.frame, ink: .label, lineHeight: frame.height)
            return (
                PlanLayoutEvidence.passingText(
                    issueIdentifier: element.identifier, issueFrame: element.frame,
                    identifier: close.identifier, frame: frame, minimum: minimum), description
            )
        }
        let reportedFrame = element.frame
        let candidates = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "plan.text."))
            .allElementsBoundByIndex.filter { candidate in
                PlanLayoutEvidence.attributedText(
                    issueIdentifier: element.identifier, issueFrame: reportedFrame,
                    identifier: candidate.identifier, frame: candidate.frame)
            }
        guard candidates.count == 1, let text = candidates.first else {
            return (false, "No unique text identifier and frame; candidates=\(candidates.count)")
        }
        let originalFrame = text.frame
        let label = text.label
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
        let scrolls = app.scrollViews.allElementsBoundByIndex.filter {
            $0.descendants(matching: .staticText).matching(identifier: text.identifier).allElementsBoundByIndex
                .contains { $0.frame == originalFrame && $0.label == label }
        }
        guard scrolls.count == 1, let scroll = scrolls.first else {
            return (false, "No unique scroll for \(text.identifier), frame=\(originalFrame)")
        }
        // System glass can cover scroll content; measure the same text in its unobscured reading position.
        guard reveal(text, in: app, scroll: scroll), text.label == label else {
            return (false, "Cannot reveal the attributed text: \(text.identifier), original=\(originalFrame)")
        }
        let current = app.staticTexts.matching(identifier: text.identifier).allElementsBoundByIndex
        guard current.count == 1, current[0].label == label, current[0].frame == text.frame else {
            return (false, "Revealed text is not unique: \(text.identifier), original=\(originalFrame)")
        }
        let traits = UITraitCollection {
            $0.userInterfaceStyle = .light
            $0.preferredContentSizeCategory = .large
        }
        let (minimum, description) = measure(
            app: app, identifier: text.identifier, label: label, frame: text.frame,
            viewport: viewport(in: app, scroll: scroll), ink: UIColor(color.color).resolvedColor(with: traits),
            lineHeight: style.uiFont(compatibleWith: traits).lineHeight)
        return (
            PlanLayoutEvidence.passingText(
                issueIdentifier: element.identifier, issueFrame: reportedFrame,
                identifier: text.identifier, frame: originalFrame, minimum: minimum),
            "reportedFrame=\(reportedFrame) originalTextFrame=\(originalFrame)\n" + description
        )
    }

    @MainActor private func viewport(in app: XCUIApplication, scroll: XCUIElement) -> CGRect {
        var frame = AuthUIFlow.viewport(in: app, scrollFrame: scroll.frame)
        let scrollBottom = frame.maxY
        let navigation = app.navigationBars.firstMatch
        if navigation.exists { frame.origin.y = max(frame.minY, navigation.frame.maxY) }
        let tabBar = app.tabBars.firstMatch
        let bottom = tabBar.exists ? min(scrollBottom, tabBar.frame.minY) : scrollBottom
        frame.size.height = max(0, bottom - frame.minY)
        return frame
    }

    @MainActor private func reveal(_ text: XCUIElement, in app: XCUIApplication, scroll: XCUIElement) -> Bool {
        for _ in 0..<12 {
            do { _ = try UIWait.stableFrames([text, scroll], timeout: 5) } catch { return false }
            let viewport = viewport(in: app, scroll: scroll)
            if viewport.contains(text.frame) { return true }
            guard let gesture = AuthScrollGesture.reveal(text.frame, in: viewport) else { return false }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(
                CGVector(dx: gesture.start.x - app.frame.minX, dy: gesture.start.y - app.frame.minY))
            let end = origin.withOffset(
                CGVector(dx: gesture.end.x - app.frame.minX, dy: gesture.end.y - app.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return false
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
