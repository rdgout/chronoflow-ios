import AppCore
import UIKit
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

    @MainActor func testAppTabsConfigureNativeScrollMinimization() async throws {
        guard #available(iOS 26, *) else { throw XCTSkip("System tab minimization requires iOS 26") }
        let host = try AuthTestHost(
            AppTabs(), size: try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "17e" }).size)
        defer { host.close() }
        try await host.settleLayout { [host.controller.view.bounds] }
        func tabController(in controller: UIViewController) -> UITabBarController? {
            (controller as? UITabBarController) ?? controller.children.lazy.compactMap { tabController(in: $0) }.first
        }
        let tabs = try XCTUnwrap(tabController(in: host.controller))
        XCTAssertEqual(tabs.tabBarMinimizeBehavior, .onScrollDown)
        XCTAssertEqual(tabs.tabBar.items?.count, 3)
    }

    @MainActor
    func testRootCanMountTheResolvedRouteImmediately() {
        for route in Route.allCases {
            XCTAssertEqual(RootNavigator(route: route).route, route)
        }
    }
}
