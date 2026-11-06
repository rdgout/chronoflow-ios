import AppCore
import XCTest

@testable import ChronoFlow

nonisolated final class RootNavigationTests: XCTestCase {
    @MainActor
    func testRootStartsUnresolvedAndNavigatesToEveryRoute() {
        let navigator = RootNavigator()
        XCTAssertNil(navigator.route)
        for route in Route.allCases {
            navigator.navigate(to: route)
            XCTAssertEqual(navigator.route, route)
        }
    }

    @MainActor
    func testRootCanMountTheResolvedRouteImmediately() {
        for route in Route.allCases {
            XCTAssertEqual(RootNavigator(route: route).route, route)
        }
    }
}
