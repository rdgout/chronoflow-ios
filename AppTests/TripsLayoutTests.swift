import DesignSystem
import PlanUI
import SwiftUI
import UIKit
import XCTest

nonisolated final class TripsLayoutTests: XCTestCase {
    @MainActor func testListEmptyAndLoadingStayInsideEveryRailAtXXLarge() async throws {
        try await AuthTestHost.registerFonts()
        let formatter = try await PlanScreenFixture.formatter()
        for fixture in try AuthDeviceFixture.all() where ["se", "17e", "duo"].contains(fixture.name) {
            for language in ["en", "nl"] {
                for state in TripsSnapshotState.allCases {
                    let screen = try tripsFixture(state, formatter: formatter)
                    let content = PlanMeasuredContent()
                    let host = try AuthTestHost(
                        NavigationStack { screen }.capturePlanContent(in: content), size: fixture.size,
                        insets: fixture.insets, language: language, category: .extraExtraLarge, scale: fixture.scale)
                    defer { host.close() }
                    try await host.settle()
                    try await assertPlanScrollFits(host, content: content, horizontalGutter: PlanUITokens.space4)
                }
            }
        }
    }
}
