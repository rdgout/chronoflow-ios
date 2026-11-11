import AppCore
import Testing

@Suite struct GuestSecretStoreTests {
    @Test func rotationStoresNewSecretAndDeletesOnlyOldToken() async throws {
        let store: any GuestSecretStore = MemoryGuestSecretStore()
        try await store.set("old-secret", for: "old")
        try await store.set("unrelated-secret", for: "unrelated")
        try await store.rotate(from: "old", to: "new", secret: "new-secret")
        #expect(try await store.get(for: "old") == nil)
        #expect(try await store.get(for: "new") == "new-secret")
        #expect(try await store.get(for: "unrelated") == "unrelated-secret")
    }

    @Test func firstMintAndSameTokenRotationRetainNewSecret() async throws {
        let store: any GuestSecretStore = MemoryGuestSecretStore()
        try await store.rotate(from: nil, to: "token", secret: "first")
        #expect(try await store.get(for: "token") == "first")
        try await store.rotate(from: "token", to: "token", secret: "replacement")
        #expect(try await store.get(for: "token") == "replacement")
    }

    @Test func discardIsPerTokenAndIdempotent() async throws {
        let store: any GuestSecretStore = MemoryGuestSecretStore()
        try await store.set("discarded", for: "discard")
        try await store.set("retained", for: "retain")
        try await store.delete(for: "discard")
        try await store.delete(for: "discard")
        #expect(try await store.get(for: "discard") == nil)
        #expect(try await store.get(for: "retain") == "retained")
    }

    @Test func deleteAllRemovesEveryTokenAndAllowsFreshMint() async throws {
        let store: any GuestSecretStore = MemoryGuestSecretStore()
        try await store.set("first-secret", for: "first")
        try await store.set("second-secret", for: "second")
        try await store.deleteAll()
        try await store.deleteAll()
        #expect(try await store.get(for: "first") == nil)
        #expect(try await store.get(for: "second") == nil)
        try await store.set("fresh-secret", for: "fresh")
        #expect(try await store.get(for: "fresh") == "fresh-secret")
    }
}
