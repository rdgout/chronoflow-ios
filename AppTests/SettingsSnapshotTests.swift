import AppCore
import DesignSystem
import LocalStore
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

@MainActor private struct SettingsSnapshotHome: View {
    @Environment(\.locale) private var locale
    let model: SettingsHomeModel
    var body: some View {
        // Keep List's gesture lifecycle out of profile-window teardown.
        ScrollView {
            VStack(alignment: .leading, spacing: PlanUITokens.space6) {
                Text(
                    SettingsStrings.text(
                        "Settings", language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
                )
                .font(Typography.screenPageTitleLg.font).foregroundStyle(ColorToken.foreground.color)
                .padding(.bottom, -PlanUITokens.space2)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("settings.title")
                if let account = model.state.account {
                    SettingsProfileRow(account: account, initials: model.state.initials)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PlanUITokens.space4)
                        .settingsSnapshotCard().accessibilityIdentifier("settings.profile")
                }
                if let copy = model.state.syncCopy(now: model.now, syncing: model.syncing, offline: model.offline) {
                    SettingsSyncRow(copy: copy, pending: model.state.pendingCount > 0, offline: model.offline)
                        .padding(.horizontal, PlanUITokens.space1)
                }
                #if DEBUG
                    VStack(spacing: 0) {
                        ForEach(SettingsDestination.allCases.filter { $0 != .profile }) { destination in
                            if destination != .account { Divider().overlay(ColorToken.border.color) }
                            SettingsDestinationRow(
                                destination: destination, credits: model.state.credits,
                                missingAnswers: model.state.missingAnswers
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, PlanUITokens.space4)
                            .accessibilityIdentifier("settings.\(destination.rawValue)")
                        }
                    }.settingsSnapshotCard()
                #endif
                SettingsSignOutButton(model: model)
            }.padding(.horizontal, PlanUITokens.space4).padding(.top, PlanUITokens.space1)
                .padding(.bottom, PlanUITokens.space8)
        }.background(ColorToken.background.color).foregroundStyle(ColorToken.cardForeground.color)
            .tint(ColorToken.primary.color)
    }
}

extension View {
    fileprivate func settingsSnapshotCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl)
        return background(ColorToken.card.color, in: shape)
            .overlay(shape.strokeBorder(ColorToken.border.color, lineWidth: AuthTokens.borderWidth))
    }
}

nonisolated final class SettingsSnapshotTests: XCTestCase {
    @MainActor func testHomeAndPendingContentAcrossAllProfiles() async throws {
        try await AuthTestHost.registerFonts()
        for fixture in try AuthDeviceFixture.all() where fixture.device != nil {
            let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
            defer { host.close() }
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                        let variant = PlanSnapshotVariant(style: style, language: language, category: category)
                        host.configure(
                            SettingsSnapshotHome(model: try settingsFixture()),
                            style: style, language: language, category: category)
                        try await host.settle()
                        let home = try capture(
                            host, fixture: fixture, required: ["settings.title", "settings.profile", "settings.sync"])
                        try verifyPlanSnapshot(
                            home, suite: "Settings", state: "home", fixture: fixture, variant: variant)
                        host.configure(
                            SignOutPendingContent(model: try settingsFixture(pending: true)),
                            style: style, language: language, category: category)
                        try await host.settle()
                        let pending = try capture(
                            host, fixture: fixture, required: ["settings.pending.title", "settings.pending.items"])
                        try verifyPlanSnapshot(
                            pending, suite: "Settings", state: "pending", fixture: fixture, variant: variant)
                    }
                }
            }
        }
    }

    @MainActor func testHomeCaptureUsesSharedRowsWithoutACollectionView() async throws {
        try await AuthTestHost.registerFonts()
        let fixture = try XCTUnwrap(AuthDeviceFixture.authSnapshotProfiles().first)
        let model = try settingsFixture()
        let host = try AuthTestHost(
            SettingsSnapshotHome(model: model), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer { host.close() }
        try await host.settle()
        _ = try capture(host, fixture: fixture, required: ["settings.title", "settings.profile", "settings.sync"])
        func check(_ view: UIView) {
            XCTAssertFalse(view is UICollectionView, "Profile captures must not instantiate List's collection view")
            XCTAssertFalse(view is UITableView, "Profile captures must not instantiate List's table view")
            view.subviews.forEach(check)
        }
        check(host.controller.view)
    }

    @MainActor func testCaptureRejectsBlankContent() throws {
        let fixture = try XCTUnwrap(AuthDeviceFixture.authSnapshotProfiles().first)
        let host = try AuthTestHost(
            ColorToken.background.color, size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer { host.close() }
        XCTAssertThrowsError(try capture(host, fixture: fixture, required: ["settings.pending.title"]))
    }

    @MainActor private func capture(
        _ host: AuthTestHost, fixture: AuthDeviceFixture, required: [String]
    ) throws -> UIImage {
        let image = try host.image()
        let frames = contentFrames(host, fixture: fixture)
        let raster = try SnapshotRaster(image: XCTUnwrap(image.cgImage))
        guard raster.width == Int(fixture.size.width * fixture.scale),
            raster.height == Int(fixture.size.height * fixture.scale)
        else { throw CaptureFailure.invalid("Capture does not match the profile dimensions") }
        let viewport = host.window.bounds.inset(by: fixture.insets)
        for identifier in required {
            guard let frame = frames[identifier] else {
                throw CaptureFailure.invalid("Missing \(identifier); refusing to record")
            }
            let visible = frame.intersection(viewport)
            guard !visible.isNull, !visible.isEmpty,
                AuthSnapshotCapture.hasInk(raster, in: visible, scale: fixture.scale)
            else { throw CaptureFailure.invalid("Blank \(identifier); refusing to record") }
        }
        return image
    }

    @MainActor private func contentFrames(_ host: AuthTestHost, fixture: AuthDeviceFixture) -> [String: CGRect] {
        var visited: Set<ObjectIdentifier> = []
        var frames: [String: CGRect] = [:]
        let window = host.window
        let insets = fixture.insets
        func check(_ element: NSObject) {
            guard visited.insert(ObjectIdentifier(element)).inserted else { return }
            if let identifier = (element as? any UIAccessibilityIdentification)?.accessibilityIdentifier,
                identifier.hasPrefix("settings."),
                !["settings.screen", "settings.pending"].contains(identifier)
            {
                let frame = window.convert(element.accessibilityFrame, from: nil)
                if !frame.isEmpty, !frame.isInfinite {
                    frames[identifier] = frame
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
        check(host.controller.view)
        return frames
    }

    private enum CaptureFailure: Error { case invalid(String) }
}
