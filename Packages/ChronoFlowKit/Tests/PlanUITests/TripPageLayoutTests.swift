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
}
