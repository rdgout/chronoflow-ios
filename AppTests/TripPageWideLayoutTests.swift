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
            await host.recordFailures {
                try await host.settle("Initial phone timeline") {
                    context.model.plan.prepared != nil && context.timelineReady
                }
                let dayID = try XCTUnwrap(context.model.anchor.dayID)
                let timelineID = "trip.timeline.\(dayID)"
                try await host.settle("Initial timeline measurement") { measurements.frame(for: timelineID) != nil }
                let scroll = try pageScroll(host)
                @MainActor func currentDayTop() -> CGFloat? {
                    measurements.frame(for: "trip.day.\(dayID)").map {
                        $0.minY - scroll.convert(scroll.bounds, to: host.window).minY
                    }
                }
                scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentOffset.y + 180), animated: false)
                try await host.settle("Initial day scroll") { context.model.currentAnchor.offset > 0 }
                let anchor = context.model.currentAnchor
                let dayTop = try XCTUnwrap(currentDayTop())
                let block = try XCTUnwrap(context.model.plan.prepared?.days.first { $0.id == dayID }?.blocks.first)
                context.model.selectBlock(block.id, formatter: formatter)
                try await host.settle("Step presentation completion") {
                    guard let sheet = host.controller.presentedViewController else { return false }
                    return !sheet.isBeingPresented && sheet.transitionCoordinator == nil
                }
                let sheet = try XCTUnwrap(host.controller.presentedViewController)

                UIView.performWithoutAnimation { host.window.frame.size = CGSize(width: 669, height: 951) }
                try await host.settle(
                    "Phone to wide: offset \(context.model.currentAnchor.offset), expected \(anchor.offset), day top \(String(describing: currentDayTop())), expected \(dayTop), list \(String(describing: measurements.frame(for: "trip.wide.list.\(dayID)")))"
                ) {
                    measurements.frame(for: "trip.wide.list.\(dayID)")?.width == 280
                        && abs(context.model.currentAnchor.offset - anchor.offset) < 1
                        && abs((currentDayTop() ?? .infinity) - dayTop) < 1
                }
                XCTAssertEqual(context.model.anchor.dayID, dayID)
                XCTAssertEqual(context.model.selectedStep?.id, block.id)
                XCTAssertTrue(host.controller.presentedViewController === sheet)
                XCTAssertTrue(try pageScroll(host) === scroll)
                let wideDayTop = try XCTUnwrap(currentDayTop())
                XCTAssertEqual(wideDayTop, dayTop, accuracy: 1)

                UIView.performWithoutAnimation { host.window.frame.size = CGSize(width: 466, height: 678) }
                try await host.settle(
                    "Wide to phone: offset \(context.model.currentAnchor.offset), expected \(anchor.offset), day top \(String(describing: currentDayTop())), expected \(dayTop)"
                ) {
                    measurements.frame(for: "trip.wide.list.\(dayID)") == nil
                        && abs(context.model.currentAnchor.offset - anchor.offset) < 1
                        && abs((currentDayTop() ?? .infinity) - dayTop) < 1
                }
                XCTAssertEqual(context.model.anchor.dayID, dayID)
                XCTAssertEqual(context.model.selectedStep?.id, block.id)
                XCTAssertTrue(host.controller.presentedViewController === sheet)
                XCTAssertTrue(try pageScroll(host) === scroll)
                let phoneDayTop = try XCTUnwrap(currentDayTop())
                XCTAssertEqual(phoneDayTop, dayTop, accuracy: 1)
            }
            await host.recordFailures { try await dismissStep(in: host, context: context) }
            await host.recordFailures { try await context.close() }
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
            if top { XCTAssertEqual(scroll.contentOffset.y, -scroll.adjustedContentInset.top, accuracy: 0.5) }
            if state == .ready {
                let dayID = try XCTUnwrap(
                    top ? context.model.plan.prepared?.days.first?.id : context.model.anchor.dayID)
                let listID = "trip.wide.list.\(dayID)"
                let timelineID = "trip.wide.timeline.\(dayID)"
                try await host.settle {
                    measurements.frame(for: timelineID) != nil && measurements.frame(for: listID) != nil
                }
                if scrolled {
                    let revision = measurements.revision(for: listID)
                    let timelineTop = try XCTUnwrap(measurements.frame(for: timelineID)).minY
                    let previousOffset = scroll.contentOffset.y
                    scroll.setContentOffset(CGPoint(x: 0, y: previousOffset + 480), animated: false)
                    try await host.settle("Post-scroll pinned list measurement") {
                        guard let list = measurements.frame(for: listID),
                            let timeline = measurements.frame(for: timelineID),
                            let header = measurements.frame(for: "trip.compactHeader")
                        else { return false }
                        let delta = scroll.contentOffset.y - previousOffset
                        return context.model.currentAnchor.offset > 0
                            && measurements.revision(for: listID) > revision
                            && abs(timeline.minY - (timelineTop - delta)) < 0.5
                            && list.minY >= header.maxY - 0.5
                    }
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
                    XCTAssertGreaterThanOrEqual(list.minY, header.maxY - 0.5)
                    let day = try XCTUnwrap(measurements.frame(for: "trip.day.\(dayID)"))
                    XCTAssertLessThanOrEqual(list.maxY, day.maxY + 0.5)
                    XCTAssertGreaterThan(list.height, 0)
                    XCTAssertGreaterThan(header.height, 0)
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
            let navigation = try XCTUnwrap(navigationController(in: host.controller))
            XCTAssertFalse(navigation.navigationBar.isHidden)
            if state == .ready {
                let item = try XCTUnwrap(navigation.navigationBar.topItem)
                let trip = try XCTUnwrap(context.model.plan.detail?.trip)
                XCTAssertEqual(item.title, "\(trip.from.iata) → \(trip.to.iata)")
                if checkMenu { XCTAssertNotNil(item.titleMenuProvider) }
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
            let host = try AuthTestHost(
                NavigationStack { page }
                    .environment(\.planPageSafeBounds, nil)
                    .environment(\.planUITestOptions, PlanUITestOptions(startAtSummary: top))
                    .capturePlanContent(in: measurements)
                    .transaction {
                        $0.disablesAnimations = true
                        $0.animation = nil
                    },
                size: CGSize(width: width, height: height), style: style, language: language, category: category)
            let chrome = TripSnapshotChrome(style: style)
            host.prepareCapture = chrome.prepare
            return host
        }

        @MainActor private func dismissStep(in host: AuthTestHost, context: TripSnapshotContext) async throws {
            context.model.selectedStep = nil
            if let sheet = host.controller.presentedViewController {
                await withCheckedContinuation { continuation in
                    sheet.dismiss(animated: false) { continuation.resume() }
                }
            }
            try await host.settle("Step dismissal completion") { host.controller.presentedViewController == nil }
        }

        @MainActor private func navigationController(in controller: UIViewController) -> UINavigationController? {
            if let navigation = controller as? UINavigationController { return navigation }
            return controller.children.compactMap { navigationController(in: $0) }.first
        }

        @MainActor private func pageScroll(_ host: AuthTestHost) throws -> UIScrollView {
            try XCTUnwrap(authScrollViews(host.controller.view).first)
        }
    }
#endif
