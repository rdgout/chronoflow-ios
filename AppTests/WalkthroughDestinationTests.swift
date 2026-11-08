import AppCore
import LocalStore
import SwiftUI
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class WalkthroughDestinationTests: XCTestCase {
    @MainActor func testReadySessionMountsWalkthroughWithoutInput() async throws {
        try await checkPresentation(delayed: nil)
    }

    @MainActor func testSessionBecomingReadyAfterMountShowsWalkthroughWithoutInput() async throws {
        try await checkPresentation(delayed: .session)
    }

    @MainActor func testDatabaseBecomingReadyAfterMountShowsWalkthroughWithoutInput() async throws {
        try await checkPresentation(delayed: .database)
    }

    private enum Delayed { case session, database }

    @MainActor private func checkPresentation(delayed: Delayed?) async throws {
        try await AuthTestHost.registerFonts()
        let root = FileManager.default.temporaryDirectory.appending(path: "walkthrough-destination-\(UUID())")
        let accountStore: (@MainActor (SessionAccountDatabase) -> any SessionAccountStore)?
        if delayed == .database {
            accountStore = { _ in WalkthroughDestinationDeferredStore() }
        } else {
            accountStore = nil
        }
        let native = NativeSessionController(
            applicationSupport: root, namespace: .mock, credentials: WalkthroughDestinationCredentials(),
            accountStore: accountStore)
        let accounts = native.accounts
        addTeardownBlock {
            try await accounts.close()
            try FileManager.default.removeItem(at: root)
        }
        let account = SessionAccount(
            id: "019a562b-8000-7000-8000-000000000001", name: "Test", email: "test@example.test",
            hasVerifiedEmail: true,
            policies: AccountPolicies(termsVersion: "1", privacyVersion: "1", acceptedTermsVersion: "1"),
            walkthroughSeen: false)
        let result = SessionResult(token: "test-token", account: account)
        if delayed != .session { try await native.controller.accept(result) }
        let device = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "17e" })
        let host = try AuthTestHost(
            WalkthroughDestination(native: native), size: device.size, insets: device.insets, scale: device.scale)
        defer { host.close() }
        host.window.layoutIfNeeded()
        if delayed != nil {
            // Let the mounted task encounter the missing dependency before making it available.
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertNil(element("walkthrough.counter", in: host.window))
            if delayed == .session {
                try await native.controller.accept(result)
            } else {
                try await native.accounts.open(accountID: AccountID(account.id))
                try await native.accounts.upsert(account)
            }
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while element("walkthrough.counter", in: host.window) == nil, ContinuousClock.now < deadline {
            host.window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let counter = try XCTUnwrap(
            element("walkthrough.counter", in: host.window), "Mounted destination must create and show its model")
        XCTAssertEqual(counter.accessibilityLabel, "1 OF 3")
        XCTAssertNotNil(element("walkthrough.skip", in: host.window))
        XCTAssertNotNil(element("walkthrough.next", in: host.window))
    }

    @MainActor private func element(_ identifier: String, in root: NSObject) -> NSObject? {
        var visited = Set<ObjectIdentifier>()
        func find(_ object: NSObject) -> NSObject? {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
            if (object as? any UIAccessibilityIdentification)?.accessibilityIdentifier == identifier { return object }
            if let view = object as? UIView {
                for child in view.subviews {
                    if let found = find(child) { return found }
                }
            }
            let count = object.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject, let found = find(child) {
                        return found
                    }
                }
            }
            return nil
        }
        return find(root)
    }
}

private actor WalkthroughDestinationCredentials: SessionStore {
    var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

private actor WalkthroughDestinationDeferredStore: SessionAccountStore {
    func open(accountID: AccountID) {}
    func upsert(_ account: SessionAccount) {}
    func close() {}
}
