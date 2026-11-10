import Foundation
import Testing

@testable import PlanUI

struct TripPageLayoutTests {
    @Test(arguments: [599.0, 600, 899, 900])
    func portraitBreakpoints(width: Double) {
        let layout = TripPageLayout.resolve(width: width, height: 1200)
        #expect(layout.isWide == (width >= 600))
        #expect(layout.listWidth == (width < 600 ? nil : width < 900 ? 280 : 320))
    }

    @Test(arguments: [599.0, 600, 669, 899, 900, 1200])
    func landscapeStaysPhone(width: Double) {
        #expect(!TripPageLayout.resolve(width: width, height: 466).isWide)
        #expect(TripPageLayout.resolve(width: width, height: 466).listWidth == nil)
    }

    @Test(arguments: [320.0, 375, 390, 393, 402, 420, 430, 440, 466])
    func phoneWidthsStayPhone(width: Double) {
        #expect(!TripPageLayout.resolve(width: width, height: 951).isWide)
    }

    @Test func unfoldedPortraitUsesWideAndSquareStaysPhone() {
        #expect(TripPageLayout.resolve(width: 669, height: 951).listWidth == 280)
        #expect(!TripPageLayout.resolve(width: 669, height: 669).isWide)
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
}
