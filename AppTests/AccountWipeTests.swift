import AppCore
import Foundation
import LocalStore
import XCTest

@testable import ChronoFlow

nonisolated final class AccountWipeTests: XCTestCase {
    @MainActor
    func testForcedWipeClearsKeychainDetachesModelAndPreservesDevicePreferences() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hosted-wipe-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = KeychainSessionStore(service: "net.chronoflow.tests.wipe." + UUID().uuidString)
        let suite = "net.chronoflow.tests.preferences." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("nl", forKey: "language")
        defaults.set("dark", forKey: "appearance")
        let preferences = DevicePreferences(suiteName: suite)
        try await preferences.writeDeviceID("019a562b-8000-7000-8000-000000000099")
        var signedOut = false
        let native = NativeSessionController(
            applicationSupport: root, namespace: .mock, credentials: credentials,
            signedOut: { signedOut = true })
        native.observe()
        let id = "019a562b-8000-7000-8000-000000000001"
        try await native.controller.accept(
            SessionResult(
                token: "test-token",
                account: SessionAccount(
                    id: id, name: "Test", email: "a@example.test", hasVerifiedEmail: true,
                    policies: AccountPolicies(termsVersion: "1", privacyVersion: "1"), walkthroughSeen: true)))
        let activeDatabase = await native.accounts.activeDatabase()
        let database = try XCTUnwrap(activeDatabase)
        _ = try await OutboxRepository(database: database).enqueue(.walkthrough)
        let pending = try await native.controller.signOut(discardPending: false)
        XCTAssertEqual(pending, .needsConfirmation(pendingCount: 1))
        let directory = await database.directory(for: try AccountID(id))
        let result = try await native.controller.signOut(discardPending: true, unauthorized: true)
        XCTAssertEqual(result, .signedOut)
        XCTAssertTrue(signedOut)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let stored = try await credentials.read()
        XCTAssertNil(stored)
        XCTAssertEqual(native.model.state, .unknown)
        let deviceID = try await preferences.readDeviceID()
        XCTAssertEqual(deviceID, "019a562b-8000-7000-8000-000000000099")
        XCTAssertEqual(defaults.string(forKey: "language"), "nl")
        XCTAssertEqual(defaults.string(forKey: "appearance"), "dark")
        await native.stopObserving()
    }
}
