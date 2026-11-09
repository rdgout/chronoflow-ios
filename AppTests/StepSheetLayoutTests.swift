import DesignSystem
import PlanCore
import PlanUI
import SwiftUI
import UIKit
import XCTest

nonisolated final class StepSheetLayoutTests: XCTestCase {
    @MainActor func testStepTitleKeepsItsFullColumnAndScaledBoardLineHeight() async throws {
        try await AuthTestHost.registerFonts()
        let formatter = try await PlanScreenFixture.formatter()
        let detail = try PlanScreenFixture.detail()
        let block = try XCTUnwrap(detail.plan.blocks.first { $0.type == .avoidLight })
        let style = Typography.screenCardTitle
        for fixture in try AuthDeviceFixture.layoutStressProfiles() {
            for language in ["en", "nl"] {
                let category = UIContentSizeCategory.extraExtraLarge
                let content = PlanMeasuredContent()
                let host = try AuthTestHost(
                    StepSheet(
                        detail: detail, blockID: block.id, now: PlanScreenFixture.now, formatter: formatter,
                        change: { _ in }
                    ).capturePlanContent(in: content),
                    size: fixture.size, insets: fixture.insets, language: language, category: category,
                    scale: fixture.scale)
                defer { host.close() }
                try await host.settleLayout { content.frames }
                let font = style.uiFont(compatibleWith: .init(preferredContentSizeCategory: category))
                let left = fixture.insets.left + PlanUITokens.space5 + PlanUITokens.space8 + PlanUITokens.space3
                let right = fixture.size.width - fixture.insets.right - PlanUITokens.space5
                let title = try XCTUnwrap(
                    content.frames.filter {
                        abs($0.minX - left) <= 1 && $0.height >= font.lineHeight - 1
                    }.min { $0.minY < $1.minY },
                    "Missing title: \(fixture.name) \(language) \(category.rawValue)")
                XCTAssertEqual(title.maxX, right, accuracy: 1)
                let lineHeight = try XCTUnwrap(style.lineHeight) * font.pointSize / style.size
                XCTAssertGreaterThanOrEqual(title.height, lineHeight - 1)
                let text = PlanStrings.text("Avoid bright light", language: language == "nl" ? .nl : .en)
                let bounds = (text as NSString).boundingRect(
                    with: CGSize(width: right - left, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
                XCTAssertGreaterThanOrEqual(title.height, bounds.height - 1)
                try await assertPlanScrollFits(host, content: content)

            }
        }
    }

    @MainActor func testContentCollectorMeasuresOverflowAndReconfiguration() async throws {
        let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "duo" })
        let content = PlanMeasuredContent()
        func probe(offset: CGFloat) -> some View {
            ScrollView {
                Text(verbatim: "Geometry probe")
                    .frame(width: 64, height: 64).padding(.leading, offset).planContentBounds()
                    .padding(PlanUITokens.space4).frame(maxWidth: .infinity)
            }.capturePlanContent(in: content)
        }
        let host = try AuthTestHost(
            probe(offset: fixture.size.width), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer { host.close() }
        try await host.settleLayout { content.frames }
        XCTAssertEqual(content.frames.count, 1)
        XCTAssertTrue(content.frames.contains { $0.maxX > fixture.size.width - fixture.insets.right })
        host.configure(probe(offset: 0))
        try await host.settleLayout { content.frames }
        let frame = try XCTUnwrap(content.frames.first)
        XCTAssertEqual(content.frames.count, 1)
        XCTAssertEqual(frame.size, CGSize(width: 64, height: 64))
        XCTAssertGreaterThanOrEqual(frame.minX, fixture.insets.left)
        XCTAssertLessThanOrEqual(frame.maxX, fixture.size.width - fixture.insets.right)
    }

    @MainActor func testStepActionsAndLegendScrollWithinEveryLeanProfile() async throws {
        try await AuthTestHost.registerFonts()
        let formatter = try await PlanScreenFixture.formatter()
        let detail = try PlanScreenFixture.detail()
        let block = try XCTUnwrap(detail.plan.blocks.first { $0.actionable && $0.checkKey != nil })
        for fixture in try AuthDeviceFixture.layoutStressProfiles() {
            for language in ["en", "nl"] {
                let content = PlanMeasuredContent()
                let host = try AuthTestHost(
                    StepSheet(
                        detail: detail, blockID: block.id, now: PlanScreenFixture.now, formatter: formatter,
                        change: { _ in }
                    ).capturePlanContent(in: content),
                    size: fixture.size, insets: fixture.insets, language: language, category: .extraExtraLarge,
                    scale: fixture.scale)
                defer { host.close() }
                try await host.settleLayout { content.frames }
                try await assertPlanScrollFits(host, content: content)
                XCTAssertTrue(recoveryTextFields(host.window).isEmpty)
                host.configure(
                    LegendSheet().capturePlanContent(in: content), language: language, category: .extraExtraLarge)
                try await host.settleLayout { content.frames }
                try await assertPlanScrollFits(host, content: content)
            }
        }
    }
}

@MainActor final class PlanMeasuredContent {
    private var measurements: [UUID: (identifier: String?, frame: CGRect)] = [:]
    var frames: [CGRect] { measurements.values.map(\.frame) }

    func frame(for identifier: String) -> CGRect? {
        let matches = measurements.values.filter { $0.identifier == identifier }
        return matches.count == 1 ? matches.first?.frame : nil
    }

    func record(_ identity: UUID, _ identifier: String?, _ frame: CGRect?) {
        if let frame, !frame.isEmpty, !frame.isNull, !frame.isInfinite {
            measurements[identity] = (identifier, frame)
        } else {
            measurements[identity] = nil
        }
    }
}

extension View {
    @MainActor func capturePlanContent(in content: PlanMeasuredContent) -> some View {
        environment(\.planContentMeasure, content.record)
    }
}

@MainActor func assertPlanScrollFits(
    _ host: AuthTestHost, content: PlanMeasuredContent, horizontalGutter: CGFloat = 0
) async throws {
    let scrolls = authScrollViews(host.controller.view)
    XCTAssertFalse(scrolls.isEmpty)
    for scroll in scrolls where !scroll.isHidden && scroll.bounds.width > 0 {
        XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
        let outer = scroll.convert(scroll.bounds, to: host.window)
        let adjusted = scroll.adjustedContentInset
        let visible = PlanLayoutEvidence.contentViewport(
            scroll: outer, top: adjusted.top, left: adjusted.left, bottom: adjusted.bottom, right: adjusted.right)
        let safe = host.container.insets ?? .init(top: 0, left: 0, bottom: 0, right: 0)
        let context =
            "window=\(host.window.bounds) safe=\(safe) scroll=\(outer) adjusted=\(adjusted) viewport=\(visible)"
        XCTAssertGreaterThan(visible.width, 0, context)
        XCTAssertGreaterThan(visible.height, 0, context)
        let safeFrame = CGRect(
            x: safe.left, y: safe.top, width: host.window.bounds.width - safe.left - safe.right,
            height: host.window.bounds.height - safe.top - safe.bottom)
        XCTAssertFalse(visible.intersection(safeFrame).isEmpty, context)
        for atBottom in [false, true] {
            scroll.setContentOffset(
                CGPoint(
                    x: -adjusted.left,
                    y: atBottom
                        ? max(-adjusted.top, scroll.contentSize.height - scroll.bounds.height + adjusted.bottom)
                        : -adjusted.top), animated: false)
            try await host.settleLayout { content.frames }
            XCTAssertFalse(content.frames.isEmpty, "Missing measured SwiftUI content: \(context)")
            for frame in content.frames {
                XCTAssertFalse(
                    frame.isEmpty || frame.isInfinite || frame.isNull, "Invalid content: \(frame) \(context)")
                XCTAssertGreaterThanOrEqual(
                    frame.minX, safe.left + horizontalGutter - 1, "content=\(frame) \(context)")
                XCTAssertLessThanOrEqual(
                    frame.maxX, host.window.bounds.width - safe.right - horizontalGutter + 1,
                    "content=\(frame) \(context)")
            }
        }
        XCTAssertTrue(scroll.contentOffset.y.isFinite)
    }
}
