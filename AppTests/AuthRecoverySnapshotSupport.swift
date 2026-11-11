import AppCore
import Auth
import DataAccess
import DesignSystem
import SwiftUI
import UIKit
import XCTest

@MainActor func recoverySnapshots<State: RawRepresentable, V: View>(
    screen: String, states: [State], file: StaticString = #filePath,
    view: @MainActor (State, @escaping (AuthElement, CGRect) -> Void) async throws -> V
) async throws where State.RawValue == String {
    try await AuthTestHost.registerFonts()
    for fixture in try AuthDeviceFixture.authSnapshotProfiles() {
        let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer { host.close() }
        for (style, language, category) in fixture.authSnapshotVariants {
            for state in states {
                var frames: [AuthElement: CGRect] = [:]
                host.configure(
                    try await view(state, { frames[$0] = $1 }), style: style, language: language, category: category)
                try await host.settle()
                let name =
                    "\(fixture.snapshotName)-\(style == .dark ? "dark" : "light")-\(language)-\(DynamicTypeSize(category).map { String(describing: $0) } ?? category.rawValue)-\(state.rawValue)"
                let directory = URL(filePath: "\(file)").deletingLastPathComponent().appending(
                    path: "__Snapshots__/Auth/\(screen)")
                let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
                let failure = try AuthSnapshotCapture.verify(
                    png: XCTUnwrap(host.image().pngData()), size: fixture.size, scale: fixture.scale,
                    viewport: CGRect(origin: .zero, size: fixture.size).inset(by: fixture.insets),
                    frames: Dictionary(uniqueKeysWithValues: frames.map { ($0.key.rawValue, $0.value) }),
                    required: Set(frames.keys.map(\.rawValue)).union(["brand", "heading", "subtitle", "card", "submit"]
                    ),
                    reference: directory.appending(path: "\(name).png"), record: record)
                if record {
                    XCTAssertTrue(failure?.hasPrefix("Record mode is on.") == true)
                } else if let failure {
                    XCTFail(failure)
                }
            }
        }
    }
}

@MainActor func recoverySource() throws -> MockDataSource {
    let settings = AccountSettings(
        bodyClock: JSONObject(), sleepAnswered: false, preferences: JSONObject(),
        reminders: JSONObject(), planCredits: JSONObject(),
        policies: AccountPolicies(termsVersion: "1", privacyVersion: "1"))
    let snapshot = AccountSnapshot(
        id: "0199a3c0-0000-7000-8000-000000000000", name: "Rick", email: "demo@example.com",
        hasVerifiedEmail: true, settings: settings, readiness: JSONObject(), billing: JSONObject(),
        security: JSONObject())
    return MockDataSource(
        seed: MockServerState(accounts: [MockServerAccount(snapshot: snapshot, password: "fixture")]), delay: { 0 },
        sleep: { _ in })
}

@MainActor func recoveryLayout<V: View>(
    view: @MainActor (@escaping (AuthElement, CGRect) -> Void) async throws -> V
) async throws {
    try await AuthTestHost.registerFonts()
    for fixture in try AuthDeviceFixture.layoutStressProfiles() {
        for language in ["en", "nl"] {
            var frames: [AuthElement: CGRect] = [:]
            var insets = fixture.insets
            insets.bottom = max(insets.bottom, fixture.name.hasPrefix("duo") ? 264 : 218)
            let host = try AuthTestHost(
                try await view { frames[$0] = $1 }, size: fixture.size, insets: insets, language: language,
                category: .extraExtraLarge, scale: fixture.scale)
            defer { host.close() }
            try await host.settleLayout { Array(frames.values) }
            let required: Set<AuthElement> = [.brand, .heading, .subtitle, .card, .submit]
            XCTAssertTrue(required.isSubset(of: Set(frames.keys)), "Missing required recovery content: \(frames.keys)")
            for (element, frame) in frames {
                XCTAssertGreaterThanOrEqual(frame.minX, insets.left + AuthTokens.gutter - 0.5, element.rawValue)
                XCTAssertLessThanOrEqual(
                    frame.maxX, fixture.size.width - insets.right - AuthTokens.gutter + 0.5, element.rawValue)
            }
            let scroll = try XCTUnwrap(authScrollViews(host.controller.view).first)
            scroll.setContentOffset(
                CGPoint(
                    x: 0,
                    y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)),
                animated: false)
            try await host.settleLayout { Array(frames.values) }
            let viewport = scroll.convert(scroll.bounds, to: host.window).intersection(
                host.window.bounds.inset(by: insets))
            let last = frames[.footer] ?? frames[.backToSignIn] ?? frames[.submit]
            XCTAssertTrue(viewport.contains(try XCTUnwrap(last)), "Last control outside \(fixture.name), \(language)")
        }
    }
}

@MainActor func recoveryTextFields(_ view: UIView) -> [UITextField] {
    (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(recoveryTextFields)
}

@MainActor func authTopCapture<V: View>(
    required: Set<AuthElement>,
    view: @MainActor (@escaping (AuthElement, CGRect) -> Void) async throws -> V
) async throws {
    try await AuthTestHost.registerFonts()
    let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "se" })
    for style in [UIUserInterfaceStyle.light, .dark] {
        var frames: [AuthElement: CGRect] = [:]
        let host = try AuthTestHost(
            try await view { frames[$0] = $1 }, size: fixture.size, insets: fixture.insets,
            style: style, language: "nl", category: .extraExtraLarge, scale: fixture.scale)
        defer { host.close() }
        try await host.settle()
        let raster = try SnapshotRaster(image: XCTUnwrap(host.image().cgImage))
        let failure = AuthSnapshotCapture.failure(
            raster: raster, size: fixture.size, scale: host.scale,
            viewport: host.window.bounds.inset(by: fixture.insets),
            frames: Dictionary(uniqueKeysWithValues: frames.map { ($0.key.rawValue, $0.value) }),
            required: Set(Set(frames.keys).union(required).map(\.rawValue)).union([
                "brand", "heading", "subtitle", "card", "submit",
            ]))
        XCTAssertNil(failure, "\(style): \(failure ?? "")")
    }
}
