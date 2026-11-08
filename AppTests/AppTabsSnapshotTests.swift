import AppCore
import DesignSystem
import LocalStore
import PlanUI
import SwiftUI
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class AppTabsSnapshotTests: XCTestCase {
    @MainActor func testSystemTabs() async throws {
        try await AuthTestHost.registerFonts()
        let directory = FileManager.default.temporaryDirectory.appending(path: "tabs-snapshot-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let native = NativeSessionController(
            applicationSupport: directory, namespace: .mock, credentials: TabsSnapshotCredentials())
        do {
            try await seedEmptyAccount(native)
            for fixture in try AuthDeviceFixture.authSnapshotProfiles() {
                for variant in PlanSnapshotVariant.all {
                    let host = SystemTabsSnapshotHost(AppTabs(native: native), fixture: fixture, variant: variant)
                    defer { host.close() }
                    let image = try await host.capture(selectedIndex: 1, contentIdentifier: "trips.empty")
                    let items = try XCTUnwrap(host.requireTabBar(selectedIndex: 1).items)
                    let language: Language = variant.language == "nl" ? .nl : .en
                    XCTAssertEqual(
                        items.map(\.title),
                        ["Today", "My trips", "Settings"].map {
                            PlanStrings.text($0, language: language)
                        })
                    try verifyPlanSnapshot(image, suite: "Tabs", state: "tabs", fixture: fixture, variant: variant)
                }
            }
        } catch {
            try? await native.accounts.close()
            throw error
        }
        try await native.accounts.close()
    }

    @MainActor func testCaptureRejectsMissingTabBar() throws {
        let fixture = try XCTUnwrap(AuthDeviceFixture.authSnapshotProfiles().first)
        let host = SystemTabsSnapshotHost(EmptyView(), fixture: fixture, variant: PlanSnapshotVariant.all[0])
        defer { host.close() }
        // An unwrapped placeholder must fail before the reference writer is reached, even in record mode.
        XCTAssertThrowsError(try host.requireTabBar(selectedIndex: 1))
    }

    @MainActor func testCaptureRejectsHiddenIncompleteAndBlankTabBar() async throws {
        try await AuthTestHost.registerFonts()
        let fixture = try XCTUnwrap(AuthDeviceFixture.authSnapshotProfiles().first)
        let host = SystemTabsSnapshotHost(AppTabs(), fixture: fixture, variant: PlanSnapshotVariant.all[0])
        defer { host.close() }
        let image = try await host.capture(selectedIndex: 1)
        let bar = try host.requireTabBar(selectedIndex: 1)
        bar.isHidden = true
        XCTAssertThrowsError(try host.validate(image, selectedIndex: 1))
        bar.isHidden = false
        XCTAssertThrowsError(try host.requireTabBar(selectedIndex: 0))
        let format = UIGraphicsImageRendererFormat()
        format.scale = fixture.scale
        let contentOnly = UIGraphicsImageRenderer(size: fixture.size, format: format).image { context in
            UIColor(ColorToken.background.color).setFill()
            context.fill(CGRect(origin: .zero, size: fixture.size))
            UIColor(ColorToken.foreground.color).setFill()
            context.fill(
                CGRect(
                    x: fixture.size.width / 2, y: fixture.size.height / 2,
                    width: PlanUITokens.space4, height: PlanUITokens.space4))
        }
        XCTAssertTrue(
            WelcomeSnapshotPixels.hasVisibleVariation(try SnapshotRaster(image: XCTUnwrap(contentOnly.cgImage)).bytes))
        XCTAssertThrowsError(try host.validate(contentOnly, selectedIndex: 1))
        let tabs = try XCTUnwrap(host.tabController)
        tabs.setViewControllers(Array(try XCTUnwrap(tabs.viewControllers).prefix(2)), animated: false)
        XCTAssertThrowsError(try host.requireTabBar(selectedIndex: 1))
    }

    @MainActor private func seedEmptyAccount(_ native: NativeSessionController) async throws {
        let id = "019a562b-8000-7000-8000-000000000001"
        try await native.controller.accept(
            SessionResult(
                token: "snapshot-token",
                account: SessionAccount(
                    id: id, name: "Snapshot", email: "snapshot@example.test", hasVerifiedEmail: true,
                    policies: AccountPolicies(termsVersion: "1", privacyVersion: "1", acceptedTermsVersion: "1"),
                    walkthroughSeen: true)))
        let active = await native.accounts.activeDatabase()
        try await AccountRepository(database: XCTUnwrap(active)).upsert(
            AccountRecord(
                id: id, name: "Snapshot", email: "snapshot@example.test",
                syncedAt: "2026-11-08T10:00:00Z", walkthroughSeen: true))
    }
}

private actor TabsSnapshotCredentials: SessionStore {
    private var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}
