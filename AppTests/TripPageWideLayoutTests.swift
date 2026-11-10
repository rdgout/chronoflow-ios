#if DEBUG
    import AppCore
    import DesignSystem
    import PlanCore
    import PlanUI
    import SwiftUI
    import UIKit
    import XCTest

    nonisolated final class TripPageWideLayoutTests: XCTestCase {
        override func setUp() {
            super.setUp()
            executionTimeAllowance = 60
        }

        @MainActor func testPlanWide() async throws { try await captureBoard("PlanWide", top: true) }
        @MainActor func testPlanWideDark() async throws {
            try await captureBoard("PlanWideDark", style: .dark)
        }
        @MainActor func testPlanWideScrolled() async throws {
            try await captureBoard("PlanWideScrolled", scrolled: true)
        }
        @MainActor func testPlanWideDayMenuTitle() async throws {
            try await captureBoard("PlanWideDayMenu-title", scrolled: true, checkMenu: true)
        }
        @MainActor func testPlanRemoteWide() async throws {
            try await captureBoard("PlanRemoteWide", state: .remoteLoading)
        }
        @MainActor func testPlanRemoteWideOffline() async throws {
            try await captureBoard("PlanRemoteWideOffline", state: .remoteOffline)
        }
        @MainActor func testWideDutchAtXXLarge() async throws {
            try await captureBoard("PlanWide-nl-xxLarge", language: "nl", category: .extraExtraLarge)
        }
        @MainActor func testRemoteWideDutchDarkAtXXLarge() async throws {
            try await captureBoard(
                "PlanRemoteWide-nl-dark-xxLarge", state: .remoteLoading, style: .dark, language: "nl",
                category: .extraExtraLarge)
        }
        @MainActor func testRemoteOfflineWideDutchDarkAtXXLarge() async throws {
            try await captureBoard(
                "PlanRemoteWideOffline-nl-dark-xxLarge", state: .remoteOffline, style: .dark, language: "nl",
                category: .extraExtraLarge)
        }

        @MainActor func testSizeChangeKeepsDayScrollAndPresentedStep() async throws {
            try await AuthTestHost.registerFonts()
            let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
            let context = try await TripSnapshotContext(state: .ready, language: "en")
            let measurements = PlanMeasuredContent()
            let host = try makeHost(context, formatter: formatter, measurements: measurements, width: 466, height: 678)
            defer { host.close() }
            try await host.settle { context.model.plan.prepared != nil && context.timelineReady }
            let dayID = try XCTUnwrap(context.model.anchor.dayID)
            let scroll = try pageScroll(host)
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentOffset.y + 180), animated: false)
            try await host.settle { context.model.currentAnchor.offset > 0 }
            let anchor = context.model.currentAnchor
            let dayTop =
                try XCTUnwrap(measurements.frame(for: "trip.day.\(dayID)")).minY
                - scroll.convert(scroll.bounds, to: host.window).minY
            let block = try XCTUnwrap(context.model.plan.prepared?.days.first { $0.id == dayID }?.blocks.first)
            context.model.selectBlock(block.id, formatter: formatter)
            try await host.settle { host.controller.presentedViewController != nil }
            let sheet = try XCTUnwrap(host.controller.presentedViewController)

            host.window.frame.size = CGSize(width: 669, height: 951)
            try await host.settle {
                measurements.frame(for: "trip.wide.list.\(dayID)")?.width == 280
                    && abs(context.model.currentAnchor.offset - anchor.offset) < 1
            }
            XCTAssertEqual(context.model.anchor.dayID, dayID)
            XCTAssertEqual(context.model.selectedStep?.id, block.id)
            XCTAssertTrue(host.controller.presentedViewController === sheet)
            let wideDayTop =
                try XCTUnwrap(measurements.frame(for: "trip.day.\(dayID)")).minY
                - scroll.convert(scroll.bounds, to: host.window).minY
            XCTAssertEqual(wideDayTop, dayTop, accuracy: 1)

            host.window.frame.size = CGSize(width: 466, height: 678)
            try await host.settle {
                measurements.frame(for: "trip.wide.list.\(dayID)") == nil
                    && abs(context.model.currentAnchor.offset - anchor.offset) < 1
            }
            XCTAssertEqual(context.model.anchor.dayID, dayID)
            XCTAssertEqual(context.model.selectedStep?.id, block.id)
            XCTAssertTrue(host.controller.presentedViewController === sheet)
            let phoneDayTop =
                try XCTUnwrap(measurements.frame(for: "trip.day.\(dayID)")).minY
                - scroll.convert(scroll.bounds, to: host.window).minY
            XCTAssertEqual(phoneDayTop, dayTop, accuracy: 1)
            sheet.dismiss(animated: false)
            try await context.close()
        }

        @MainActor private func captureBoard(
            _ name: String, state: TripPageState = .ready, top: Bool = false, scrolled: Bool = false,
            checkMenu: Bool = false, style: UIUserInterfaceStyle = .light, language: String = "en",
            category: UIContentSizeCategory = .large
        ) async throws {
            try await AuthTestHost.registerFonts()
            let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
            let context = try await TripSnapshotContext(state: state, language: language)
            let measurements = PlanMeasuredContent()
            let host = try makeHost(
                context, formatter: formatter, measurements: measurements, top: top,
                style: style, language: language, category: category)
            defer { host.close() }
            try await host.settle {
                context.model.state == state && context.model.plan.card != nil
                    && context.model.plan.adaptation != nil
                    && (state != .ready || context.timelineReady)
            }
            let scroll = try pageScroll(host)
            if state == .ready {
                let dayID = try XCTUnwrap(context.model.anchor.dayID)
                if scrolled {
                    scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentOffset.y + 480), animated: false)
                    try await host.settle { context.model.currentAnchor.offset > 0 }
                }
                let timeline = try XCTUnwrap(measurements.frame(for: "trip.wide.timeline.\(dayID)"))
                let list = try XCTUnwrap(measurements.frame(for: "trip.wide.list.\(dayID)"))
                XCTAssertEqual(list.width, 280, accuracy: 0.5)
                XCTAssertEqual(list.minX - timeline.maxX, PlanMetrics.wideColumnGap, accuracy: 0.5)
                XCTAssertGreaterThan(timeline.width, 0)
                XCTAssertGreaterThanOrEqual(timeline.minX, PlanMetrics.wideGutter - 0.5)
                XCTAssertLessThanOrEqual(list.maxX, 669 - PlanMetrics.wideGutter + 0.5)
                XCTAssertLessThanOrEqual(list.height, PlanMetrics.wideListMaxHeight)
                XCTAssertNil(measurements.frame(for: "trip.viewToggle"))
                if scrolled {
                    let header = try XCTUnwrap(measurements.frame(for: "trip.compactHeader"))
                    let viewportTop = scroll.convert(scroll.bounds, to: host.window).minY
                    XCTAssertGreaterThanOrEqual(list.minY, viewportTop - 0.5)
                    XCTAssertLessThan(header.minY, list.minY)
                }
                if checkMenu {
                    let menu = try XCTUnwrap(measurements.frame(for: "trip.dayMenu"))
                    XCTAssertGreaterThan(menu.width, 0)
                    XCTAssertLessThan(menu.maxY, list.minY)
                }
            } else if state == .remoteLoading {
                let timeline = try XCTUnwrap(measurements.frame(for: "trip.wide.loading.timeline"))
                let list = try XCTUnwrap(measurements.frame(for: "trip.wide.loading.list"))
                XCTAssertEqual(list.width, 280, accuracy: 0.5)
                XCTAssertEqual(list.minX - timeline.maxX, PlanMetrics.wideColumnGap, accuracy: 0.5)
                XCTAssertEqual(timeline.height, PlanMetrics.wideSkeletonHeight, accuracy: 0.5)
            } else {
                let offline = try XCTUnwrap(measurements.frame(for: "trip.remote.offline"))
                XCTAssertEqual(offline.minX, PlanMetrics.wideGutter, accuracy: 0.5)
                XCTAssertEqual(offline.maxX, 669 - PlanMetrics.wideGutter, accuracy: 0.5)
                XCTAssertNil(measurements.frame(for: "trip.wide.loading.timeline"))
                XCTAssertNil(measurements.frame(for: "trip.wide.loading.list"))
            }
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 0.5)
            let attachment = XCTAttachment(image: try host.image())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            try await context.close()
        }

        @MainActor private func makeHost(
            _ context: TripSnapshotContext, formatter: CopyLineFormatter, measurements: PlanMeasuredContent,
            width: CGFloat = 669, height: CGFloat = 951, top: Bool = false,
            style: UIUserInterfaceStyle = .light, language: String = "en",
            category: UIContentSizeCategory = .large
        ) throws -> AuthTestHost {
            var page = TripPageView(model: context.model, formatter: formatter, refresh: { nil })
            page.onFirstTimelineFrame = { context.timelineReady = true }
            return try AuthTestHost(
                NavigationStack { page }
                    .environment(\.planPageSafeBounds, nil)
                    .environment(\.planUITestOptions, PlanUITestOptions(startAtSummary: top))
                    .capturePlanContent(in: measurements)
                    .transaction {
                        $0.disablesAnimations = true
                        $0.animation = nil
                    },
                size: CGSize(width: width, height: height), style: style, language: language, category: category)
        }

        @MainActor private func pageScroll(_ host: AuthTestHost) throws -> UIScrollView {
            try XCTUnwrap(authScrollViews(host.controller.view).first { $0.accessibilityIdentifier == "trip.scroll" })
        }
    }
#endif
