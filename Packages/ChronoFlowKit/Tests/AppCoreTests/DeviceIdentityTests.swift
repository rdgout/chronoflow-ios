import Foundation
import Testing

@testable import AppCore

actor IdentityMemoryPreferences: DeviceIdentityPersistence {
    var value: String?
    private(set) var writes = 0
    var writeFails = false
    init(_ value: String? = nil) { self.value = value }
    func configure(writeFails: Bool) { self.writeFails = writeFails }
    func readDeviceID() -> String? {
        #expect(!Thread.isMainThread)
        return value
    }
    func writeDeviceID(_ value: String) throws {
        #expect(!Thread.isMainThread)
        if writeFails { throw SessionTestFailure.unavailable }
        self.value = value
        writes += 1
    }
}

struct DeviceIdentityTests {
    @Test func uuidv7Encodes48BitTimestampVersionVariantAndRandomness() throws {
        let id = try UUIDv7.generate(
            millisecondsSince1970: 0x0123_4567_89ab, randomBytes: Array(repeating: 0xff, count: 10))
        #expect(id.uuidString.lowercased() == "01234567-89ab-7fff-bfff-ffffffffffff")
        #expect(
            try UUIDv7.generate(millisecondsSince1970: 0, randomBytes: Array(repeating: 0, count: 10))
                .uuidString.lowercased() == "00000000-0000-7000-8000-000000000000")
        #expect(throws: DeviceIdentityFailure.invalidTimestamp) {
            try UUIDv7.generate(millisecondsSince1970: 1 << 48, randomBytes: Array(repeating: 0, count: 10))
        }
        #expect(throws: DeviceIdentityFailure.invalidRandomness) {
            try UUIDv7.generate(millisecondsSince1970: 0, randomBytes: [])
        }
    }

    @Test func concurrentCreationPersistsOnceAndRestartAndAccountWipeReuseIdentity() async throws {
        let preferences = IdentityMemoryPreferences()
        let store = DeviceIdentityStore(
            persistence: preferences, clock: { Date(timeIntervalSince1970: 1_700_000_000.123) },
            randomBytes: { Array(0..<10) })
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<40 { group.addTask { try await store.identity() } }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(Set(results).count == 1)
        #expect(results.first?.prefix(13) == "018bcfe5-687b")
        #expect(await preferences.writes == 1)
        let restarted = DeviceIdentityStore(persistence: preferences)
        #expect(try await restarted.identity() == results[0])
        #expect(StorageNamespace.api.directoryName != StorageNamespace.mock.directoryName)
        #expect(StorageNamespace.api.keychainService == "net.chronoflow.app.native")
        #expect(StorageNamespace.mock.keychainService == "net.chronoflow.app.native.mock")
        #expect(try await store.identity() == results[0])
    }

    @Test func realPreferencesPersistOutsideAccountNamespaces() async throws {
        let suite = "net.chronoflow.tests.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("nl", forKey: "language")
        let store = DeviceIdentityStore(persistence: DevicePreferences(suiteName: suite))
        let id = try await store.identity()
        let restarted = DeviceIdentityStore(persistence: DevicePreferences(suiteName: suite))
        #expect(try await restarted.identity() == id)
        #expect(defaults.string(forKey: "api.deviceId") == id)
        #expect(defaults.string(forKey: "language") == "nl")
        defaults.set(42, forKey: "api.deviceId")
        await #expect(throws: DeviceIdentityFailure.invalidPersistedIdentity) {
            try await DeviceIdentityStore(persistence: DevicePreferences(suiteName: suite)).identity()
        }
    }

    @Test func failedPersistenceRetriesWithoutCachingAnUnpersistedID() async throws {
        let persistence = IdentityMemoryPreferences()
        await persistence.configure(writeFails: true)
        let store = DeviceIdentityStore(persistence: persistence)
        await #expect(throws: SessionTestFailure.self) { try await store.identity() }
        #expect(await persistence.value == nil)
        await persistence.configure(writeFails: false)
        #expect(try await store.identity() == persistence.readDeviceID())
        #expect(await persistence.writes == 1)
    }

    @Test(arguments: ["garbage", UUID().uuidString, "00000000-0000-7000-0000-000000000000"])
    func corruptedPreferencesDoNotRotateDeviceIdentity(_ value: String) async throws {
        let persistence = IdentityMemoryPreferences(value)
        await #expect(throws: DeviceIdentityFailure.invalidPersistedIdentity) {
            try await DeviceIdentityStore(persistence: persistence).identity()
        }
        #expect(await persistence.writes == 0)
    }

    @Test func invalidClockAndRandomnessFailBeforePersistence() async {
        for time in [-1.0, .infinity, .nan, Double(1 << 48)] {
            let persistence = IdentityMemoryPreferences()
            let store = DeviceIdentityStore(persistence: persistence, clock: { Date(timeIntervalSince1970: time) })
            await #expect(throws: DeviceIdentityFailure.invalidTimestamp) { try await store.identity() }
            #expect(await persistence.writes == 0)
        }
    }

    @Test func deviceNameTrimsAndLimitsUnicodeCharactersWithModelFallback() {
        #expect(DeviceIdentityStore.deviceName("  Rick's iPhone\n", model: "iPhone") == "Rick's iPhone")
        #expect(DeviceIdentityStore.deviceName(" \n ", model: " iPhone ") == "iPhone")
        let name = String(repeating: "👨‍👩‍👧‍👦", count: 256)
        #expect(DeviceIdentityStore.deviceName(name, model: "iPhone").unicodeScalars.count <= 255)
        #expect(DeviceIdentityStore.deviceName(name, model: "iPhone") == String(name.prefix(36)))
    }
}
