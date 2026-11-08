import AppCore
import DesignSystem
import LocalStore
import PlanUI
import Settings
import SwiftUI
import UIKit
import XCTest

@MainActor private func settingsFixture(pending includePending: Bool = false) throws -> SettingsHomeModel {
    let settings = [
        try SettingsRecord(
            section: "readiness",
            value: JSONDocument(
                "{\"variant\":\"needs-answers\",\"missing\":[\"age\",\"shift\",\"eye\"],\"invalidSections\":[]}")),
        try SettingsRecord(section: "planCredits", value: JSONDocument("{\"credits\":2,\"unlimited\":false}")),
    ]
    let pending = [
        try OutboxRecord(
            id: "check", kind: "check-off",
            payload: .encoding(
                CheckOffChange(
                    tripID: "trip", planInputHash: "hash", type: .avoidLight, localDate: "2026-11-08", ordinal: 0,
                    status: .done)), createdAt: "2026-11-08T10:00:00Z"),
        try OutboxRecord(
            id: "sleep", kind: "settings",
            payload: JSONDocument(
                "{\"section\":\"bodyClock\",\"patch\":{\"habitual_bed\":\"23:00\",\"habitual_wake\":\"07:00\"}}"),
            createdAt: "2026-11-08T10:00:01Z"),
    ]
    return SettingsHomeModel(
        state: SettingsHomeState(
            account: AccountRecord(
                id: "snapshot", name: "Rick Gout", email: "rick@example.com", syncedAt: "2026-11-08T09:58:00Z"),
            settings: settings, outbox: includePending ? pending : []), now: Date(timeIntervalSince1970: 1_794_132_000))
}

@MainActor private struct SettingsSnapshotTabs: View {
    @Environment(\.locale) private var locale
    let model: SettingsHomeModel
    private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
    var body: some View {
        TabView {
            ColorToken.background.color.tabItem {
                Label(PlanStrings.text("Today", language: language), systemImage: "square.grid.2x2")
            }
            ColorToken.background.color.tabItem {
                Label(PlanStrings.text("My trips", language: language), systemImage: "airplane")
            }
            NavigationStack { SettingsHomeView(model: model) }
                .tabItem { Label(PlanStrings.text("Settings", language: language), systemImage: "gearshape") }
        }.tint(ColorToken.primary.color)
    }
}

nonisolated final class SettingsSnapshotTests: XCTestCase {
    @MainActor func testHomeAndNativePendingSheetAcrossAllProfiles() async throws {
        try await AuthTestHost.registerFonts()
        for fixture in try AuthDeviceFixture.all() where fixture.device != nil {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                        let variant = PlanSnapshotVariant(style: style, language: language, category: category)
                        let model = try settingsFixture()
                        let host = SystemTabsSnapshotHost(
                            SettingsSnapshotTabs(model: model), fixture: fixture, variant: variant)
                        defer { host.close() }
                        let home = try await host.capture(selectedIndex: 2, contentIdentifier: "settings.screen")
                        assertContentFits(host, root: host.controller.view)
                        try verifyPlanSnapshot(
                            home, suite: "Settings", state: "home", fixture: fixture, variant: variant)
                        host.close()
                        let pendingModel = try settingsFixture(pending: true)
                        let pendingHost = SystemTabsSnapshotHost(
                            SettingsSnapshotTabs(model: pendingModel), fixture: fixture, variant: variant)
                        defer { pendingHost.close() }
                        _ = try await pendingHost.capture(selectedIndex: 2, contentIdentifier: "settings.screen")
                        pendingModel.showsPending = true
                        let pending = try await sheetImage(pendingHost)
                        try verifyPlanSnapshot(
                            pending, suite: "Settings", state: "pending", fixture: fixture, variant: variant)
                    }
                }
            }
        }
    }

    @MainActor private func assertContentFits(_ host: SystemTabsSnapshotHost, root: UIView) {
        var visited: Set<ObjectIdentifier> = []
        var count = 0
        let window = host.container.window
        let insets = host.fixture.insets
        func check(_ element: NSObject) {
            guard visited.insert(ObjectIdentifier(element)).inserted else { return }
            if let identifier = (element as? any UIAccessibilityIdentification)?.accessibilityIdentifier,
                identifier.hasPrefix("settings."),
                !["settings.screen", "settings.pending", "settings.pending.items"].contains(identifier),
                element.isAccessibilityElement
            {
                let frame = window.convert(element.accessibilityFrame, from: nil)
                if !frame.isEmpty, !frame.isInfinite {
                    count += 1
                    XCTAssertGreaterThanOrEqual(frame.minX, insets.left - 1, "\(identifier): \(frame)")
                    XCTAssertLessThanOrEqual(
                        frame.maxX, window.bounds.width - insets.right + 1, "\(identifier): \(frame)")
                }
            }
            if let scroll = element as? UIScrollView, !scroll.isHidden, scroll.bounds.width > 0 {
                XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
            }
            if let view = element as? UIView { view.subviews.forEach(check) }
            element.accessibilityElements?.compactMap { $0 as? NSObject }.forEach(check)
            let children = element.accessibilityElementCount()
            if children > 0, children != NSNotFound {
                for index in 0..<children {
                    if let child = element.accessibilityElement(at: index) as? NSObject { check(child) }
                }
            }
        }
        check(root)
        XCTAssertGreaterThan(count, 0, "Missing Settings accessibility content for \(host.fixture.name)")
    }

    @MainActor private func sheetImage(_ host: SystemTabsSnapshotHost) async throws -> UIImage {
        func presented(_ controller: UIViewController) -> UIViewController? {
            if let modal = controller.presentedViewController { return modal }
            return controller.children.lazy.compactMap { presented($0) }.first
        }
        let deadline = ContinuousClock.now + .seconds(5)
        var previous: CGRect?
        var matches = 0
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            host.container.window.layoutIfNeeded()
            guard let modal = presented(host.controller), !modal.isBeingPresented, modal.view.window != nil else {
                continue
            }
            let frame = modal.view.convert(modal.view.bounds, to: host.container.window)
            matches = frame == previous ? matches + 1 : 0
            previous = frame
            guard matches >= 3 else { continue }
            XCTAssertTrue(frame.intersects(host.container.window.bounds))
            assertContentFits(host, root: modal.view)
            let format = UIGraphicsImageRendererFormat()
            format.scale = host.fixture.scale
            format.opaque = false
            format.preferredRange = .standard
            var rendered = false
            let window = host.container.window
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            XCTAssertTrue(rendered)
            XCTAssertEqual(image.cgImage?.width, Int(host.fixture.size.width * host.fixture.scale))
            XCTAssertEqual(image.cgImage?.height, Int(host.fixture.size.height * host.fixture.scale))
            return image
        }
        throw NSError(
            domain: "SettingsSnapshot", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Pending sheet did not present; refusing to record"])
    }
}
