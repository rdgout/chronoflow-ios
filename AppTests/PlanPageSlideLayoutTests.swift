#if DEBUG
    import AppCore
    import DesignSystem
    import Observation
    import PlanCore
    import PlanUI
    import Settings
    import SwiftUI
    import UIKit
    import XCTest

    nonisolated final class PlanPageSlideLayoutTests: XCTestCase {
        private static let size = CGSize(width: 402, height: 874)
        private static let offsets: [CGFloat] = [0, 120, 300, 40]

        override func setUp() {
            super.setUp()
            executionTimeAllowance = 60
        }

        @MainActor func testSettingsPageKeepsWidthWhileSliding() async throws {
            try await AuthTestHost.registerFonts()
            let measurements = PlanMeasuredContent()
            let slide = PageSlide()
            let host = try AuthTestHost(
                SlidingPage(slide: slide, size: Self.size) {
                    NavigationStack {
                        SettingsPage("Account", identifier: "settings.account.screen") {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 24)
                                .planContentBounds(identifier: "slide.settings.probe")
                        }
                    }
                }.capturePlanContent(in: measurements),
                size: Self.size)
            defer { host.close() }
            await host.recordFailures {
                try await assertStable("slide.settings.probe", host: host, slide: slide, measurements: measurements)
            }
        }

        @MainActor func testTripPageKeepsWidthWhileSliding() async throws {
            try await AuthTestHost.registerFonts()
            let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
            let context = try await TripSnapshotContext(state: .ready, language: "en")
            let measurements = PlanMeasuredContent()
            let slide = PageSlide()
            var page = TripPageView(model: context.model, formatter: formatter, refresh: { nil })
            page.onFirstTimelineFrame = { context.timelineReady = true }
            let host = try AuthTestHost(
                SlidingPage(slide: slide, size: Self.size) { NavigationStack { page } }
                    .capturePlanContent(in: measurements)
                    .transaction {
                        $0.disablesAnimations = true
                        $0.animation = nil
                    },
                size: Self.size)
            defer { host.close() }
            await host.recordFailures {
                try await host.settle("Initial trip timeline") {
                    context.model.plan.prepared != nil && context.timelineReady
                        && context.model.anchor.dayID != nil
                }
                let dayID = try XCTUnwrap(context.model.anchor.dayID)
                try await assertStable("trip.day.\(dayID)", host: host, slide: slide, measurements: measurements)
            }
            await host.recordFailures { try await context.close() }
        }

        /// A navigation pop translates the page without resizing it; its content must translate with it.
        @MainActor private func assertStable(
            _ identifier: String, host: AuthTestHost, slide: PageSlide, measurements: PlanMeasuredContent,
            file: StaticString = #filePath, line: UInt = #line
        ) async throws {
            // The first layout can leave a stale rail inset until the page next moves; flush it first.
            slide.dx = 1
            try await host.settleLayout { [measurements.frame(for: identifier)].compactMap { $0 } }
            var reference: CGRect?
            for dx in Self.offsets {
                slide.dx = dx
                try await host.settleLayout { [measurements.frame(for: identifier)].compactMap { $0 } }
                let frame = try XCTUnwrap(measurements.frame(for: identifier), "\(identifier) at dx \(dx)")
                guard let reference else {
                    reference = frame
                    XCTAssertGreaterThan(frame.width, 0, file: file, line: line)
                    continue
                }
                XCTAssertEqual(
                    frame.width, reference.width, accuracy: 0.5,
                    "\(identifier) width at dx \(dx): \(frame), at dx 0: \(reference)", file: file, line: line)
                XCTAssertEqual(
                    frame.minX - dx, reference.minX, accuracy: 0.5,
                    "\(identifier) leading inset at dx \(dx): \(frame), at dx 0: \(reference)", file: file, line: line)
            }
        }
    }

    @MainActor @Observable private final class PageSlide {
        var dx: CGFloat = 0
    }

    /// Mirrors AppTabs: a static root safe area above a page that moves horizontally at constant width.
    private struct SlidingPage<Page: View>: View {
        let slide: PageSlide
        let size: CGSize
        @ViewBuilder let page: () -> Page

        var body: some View {
            page().frame(width: size.width, height: size.height).offset(x: slide.dx)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .planPageSafeArea()
        }
    }
#endif
