import PlanUI
import SwiftUI
import UIKit
import XCTest

nonisolated final class TodayLayoutTests: XCTestCase {
    @MainActor func testEveryTodayStateScrollsWithinTheThreeProfilesAtXXLarge() async throws {
        try await AuthTestHost.registerFonts()
        let formatter = try await PlanScreenFixture.formatter()
        for fixture in try AuthDeviceFixture.all() where ["se", "17e", "duo"].contains(fixture.name) {
            for language in ["en", "nl"] {
                for state in TodaySnapshotState.allCases {
                    let screen = try todayFixture(state, formatter: formatter)
                    let content = PlanMeasuredContent()
                    let host = try AuthTestHost(
                        NavigationStack { screen }.capturePlanContent(in: content), size: fixture.size,
                        insets: fixture.insets, language: language, category: .extraExtraLarge, scale: fixture.scale)
                    defer { host.close() }
                    try await host.settle()
                    try await assertPlanScrollFits(host, content: content)
                }
            }
        }
    }
}
