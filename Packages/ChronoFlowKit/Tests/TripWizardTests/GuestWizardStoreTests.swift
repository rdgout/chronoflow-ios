import AppCore
import Foundation
import Testing
import TripWizard

@Suite struct GuestWizardStoreTests {
    @Test func roundTripAndInitialValues() async throws {
        let clock = WizardTestClock()
        let root = guestStoreTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GuestWizardStore(applicationSupport: root, namespace: .mock, now: { clock.now })
        var draft = try await store.start()
        #expect(draft.state.step == .whereTo && draft.form.end.kind == "one_way")
        #expect(draft.form.preparation.days == 3 && draft.state.savedProfile == nil && !draft.state.firstTrip)
        #expect(draft.state.profile["habitual_bed"] == .string("23:00"))
        #expect(draft.state.profile["habitual_wake"] == .string("07:00"))
        draft.state.step = .sleep
        draft.state.revision = 2
        draft.state.sheet = WizardAirportSheet(index: 0, side: .to)
        draft.fieldErrors = ["review": FieldMessage(key: "Check your flight dates.")]
        try await store.persist(draft)
        #expect(
            try await GuestWizardStore(applicationSupport: root, namespace: .mock, now: { clock.now }).recover()
                == draft)
        #expect(
            !FileManager.default.fileExists(
                atPath: GuestRecoveryLocation.file(applicationSupport: root, namespace: .api).path))
    }

    @Test(arguments: [1740.0, 1799.999, 1800.0, 1860.0])
    func recoveryExpiry(_ elapsed: TimeInterval) async throws {
        let clock = WizardTestClock()
        let root = guestStoreTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GuestWizardStore(applicationSupport: root, namespace: .mock, now: { clock.now })
        let draft = try await store.start()
        clock.advance(elapsed)
        #expect(try await store.recover() == (elapsed < 1800 ? draft : nil))
        if elapsed >= 1800 {
            await #expect(throws: CancellationError.self) { try await store.persist(draft) }
        }
    }

    @Test func stripsRetiredValuesAndSecretsOnWriteAndLegacyRecovery() async throws {
        let root = guestStoreTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GuestWizardStore(applicationSupport: root, namespace: .mock)
        var draft = try await store.start()
        draft.form.identity = ApiReviewIdentity(
            token: "token", inputRevision: 1, reviewRevision: 1, guestSecret: "SECRET")
        draft.state.review = try JSONDecoder().decode(
            ApiTripReview.self,
            from: Data(
                contentsOf: Bundle.module.url(forResource: "review", withExtension: "json", subdirectory: "Fixtures")!))
        draft.state.review?.identity.guestSecret = "SECRET"
        draft.state.profile["pregnancy"] = .bool(true)
        try await store.persist(draft)
        let url = GuestRecoveryLocation.file(applicationSupport: root, namespace: .mock)
        var bytes = try Data(contentsOf: url)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("SECRET"))
        #expect(!ProfilePreferences.containsRetiredValues(String(decoding: bytes, as: UTF8.self)))
        var json = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        var state = json["state"] as! [String: Any]
        var profile = state["profile"] as! [String: Any]
        profile["pregnancy"] = true
        state["profile"] = profile
        json["state"] = state
        var form = json["form"] as! [String: Any]
        var identity = form["identity"] as! [String: Any]
        identity["guestSecret"] = "LEGACY_SECRET"
        form["identity"] = identity
        json["form"] = form
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let recovered = try await store.recover()
        #expect(recovered?.state.profile["pregnancy"] == nil && recovered?.form.identity?.guestSecret == nil)
        bytes = try Data(contentsOf: url)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("LEGACY_SECRET"))
        #expect(!ProfilePreferences.containsRetiredValues(String(decoding: bytes, as: UTF8.self)))
    }

    @Test func guardsRevisionsInstancesDiscardAndSave() async throws {
        let root = guestStoreTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GuestWizardStore(applicationSupport: root, namespace: .mock)
        var first = try await store.start()
        let old = first
        first.state.revision = 3
        try await store.persist(first)
        try await store.persist(old)
        #expect(try await store.recover() == first)
        try await store.discard(instance: first.state.instance)
        await #expect(throws: CancellationError.self) { try await store.persist(first) }
        let second = try await store.start()
        try await store.discard(instance: first.state.instance)
        await #expect(throws: CancellationError.self) { try await store.persist(first) }
        #expect(try await store.recover() == second)
        try await store.didSave(instance: second.state.instance, firstTrip: true)
        #expect(try await store.recover() == nil)
    }
}

func guestStoreTestDirectory() -> URL {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return root.appendingPathComponent("build/guest-store-tests/\(UUID().uuidString)")
}
