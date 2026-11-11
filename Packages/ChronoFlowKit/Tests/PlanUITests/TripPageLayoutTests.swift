import Foundation
import Testing

@testable import PlanUI

struct TripPageLayoutTests {
    @Test(arguments: [599.0, 600, 899, 900, 1200])
    func breakpoints(width: Double) {
        let layout = TripPageLayout.resolve(width: width)
        #expect(layout.isWide == (width >= 600))
        #expect(layout.listWidth == (width < 600 ? nil : width < 900 ? 280 : 320))
    }

    @Test(arguments: [320.0, 375, 390, 393, 402, 420, 430, 440, 466])
    func phoneWidthsStayPhone(width: Double) {
        #expect(!TripPageLayout.resolve(width: width).isWide)
    }

    @Test func unfoldedDuoIsWideInBothOrientations() {
        #expect(TripPageLayout.resolve(width: 669).listWidth == 280)
        #expect(TripPageLayout.resolve(width: 951).listWidth == 320)
    }

    @Test func listSticksBelowTheWholeHeaderAndShrinksAtTheEndOfItsDay() {
        let position = TripWideListPosition(
            dayTop: -398, dayHeight: 760, viewportHeight: 850, stickyTop: 48, contentHeight: 700)
        #expect(position.offset == 446)
        #expect(position.height == 314)
        #expect(-398 + position.offset == 48)
        #expect(-398 + position.offset + position.height == -398 + 760)
    }

    @Test func shortListStaysBesideItsDayAndTallListScrollsWithinTheViewport() {
        let short = TripWideListPosition(
            dayTop: 180, dayHeight: 1200, viewportHeight: 850, stickyTop: 48, contentHeight: 220)
        #expect(short.offset == 0)
        #expect(short.height == 220)
        let tall = TripWideListPosition(
            dayTop: -100, dayHeight: 1200, viewportHeight: 650, stickyTop: 80, contentHeight: 1500)
        #expect(tall.offset == 180)
        #expect(tall.height == 570)
    }

    @Test func listDisappearsWhenItsDayPassesTheHeader() {
        let position = TripWideListPosition(
            dayTop: -800, dayHeight: 760, viewportHeight: 850, stickyTop: 48, contentHeight: 700)
        #expect(position.offset == 760)
        #expect(position.height == 0)
    }

    @Test(arguments: [true, false])
    func resizeRestoresTheSameDayOffsetAfterLateReflow(toWide: Bool) {
        let anchor = TripPageAnchor(dayID: "selected-day", labelDate: "2026-11-10", offset: 180)
        var restoration = TripScrollRestoration(anchor: anchor)
        let viewport = CGSize(width: toWide ? 669 : 466, height: toWide ? 814 : 541)
        func sample(origin: Double, offset: Double, height: Double = 12000) -> TripScrollRestoration.Sample {
            .init(
                dayOrigin: origin, contentOffset: offset, contentSize: CGSize(width: viewport.width, height: height),
                viewport: viewport, lower: 0, upper: height - viewport.height, scale: 3)
        }
        let initial = sample(origin: 1400, offset: 1580)
        #expect(restoration.observe(initial) == false)
        let shift = toWide ? 47.0 / 3 : -47.0 / 3
        let reflow = sample(origin: 1400 + shift, offset: 1580, height: 11900)
        let offsetAfterOneCorrection = reflow.contentOffset - reflow.dayOrigin
        #expect(abs(offsetAfterOneCorrection - (toWide ? 164.3333333333333 : 195.6666666666667)) < 0.000001)
        #expect(restoration.observe(reflow) == false)
        let target = restoration.target(for: reflow)
        #expect(abs((target - reflow.dayOrigin) - anchor.offset) < 0.000001)
        let restored = sample(origin: reflow.dayOrigin, offset: target, height: 11900)
        #expect(restoration.observe(restored) == false)
        #expect(restoration.observe(restored) == true)
        #expect(abs((restored.dayOrigin - restored.contentOffset) - -180) < 0.000001)
        #expect(restoration.anchor == anchor)
    }

    @Test func resizeUsesTheLiveContentOriginAndWaitsForContentSizeToSettle() {
        var restoration = TripScrollRestoration(anchor: TripPageAnchor(dayID: "day", offset: 180))
        let first = TripScrollRestoration.Sample(
            dayOrigin: 1416, contentOffset: 1500, contentSize: CGSize(width: 669, height: 5000),
            viewport: CGSize(width: 669, height: 814), lower: 0, upper: 4186, scale: 3)
        #expect(restoration.target(for: first) == 1596)
        #expect(restoration.observe(first) == false)
        let corrected = TripScrollRestoration.Sample(
            dayOrigin: 1416, contentOffset: 1596, contentSize: CGSize(width: 669, height: 5000),
            viewport: first.viewport, lower: 0, upper: 4186, scale: 3)
        #expect(restoration.observe(corrected) == false)
        let reestimated = TripScrollRestoration.Sample(
            dayOrigin: 1416, contentOffset: 1596, contentSize: CGSize(width: 669, height: 6000),
            viewport: first.viewport, lower: 0, upper: 5186, scale: 3)
        #expect(restoration.observe(reestimated) == false)
        #expect(restoration.observe(reestimated) == true)
    }

    @Test func resizeMeasuresTheAnchorBelowTheTopInset() {
        let restoration = TripScrollRestoration(anchor: TripPageAnchor(dayID: "day", offset: 0))
        let sample = TripScrollRestoration.Sample(
            dayOrigin: 1337, contentOffset: 1337, contentSize: CGSize(width: 951, height: 11070),
            viewport: CGSize(width: 951, height: 669), lower: -82, upper: 10483, scale: 3)
        #expect(restoration.target(for: sample) == 1255)
    }

    @Test func resizeClampsToTheAvailableScrollRange() {
        var restoration = TripScrollRestoration(anchor: TripPageAnchor(dayID: "last", offset: 180))
        let sample = TripScrollRestoration.Sample(
            dayOrigin: 4800, contentOffset: 4186, contentSize: CGSize(width: 669, height: 5000),
            viewport: CGSize(width: 669, height: 814), lower: 0, upper: 4186, scale: 3)
        #expect(restoration.target(for: sample) == 4186)
        #expect(restoration.observe(sample) == false)
        #expect(restoration.observe(sample) == true)
    }
}
