import Foundation
import Testing

@testable import AppCore

private actor MemorySessionStore: SessionStore {
    var data: Data?
    private(set) var deletes = 0
    init(_ data: Data?) { self.data = data }
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() {
        data = nil
        deletes += 1
    }
}

struct SessionStoreTests {
    @Test func nativeSessionRoundTripsWithoutDeleting() async throws {
        let value = StoredSession(token: "secret", accountId: "account")
        let data = try JSONEncoder().encode(value)
        #expect(StoredSession.parse(data) == value)
        let store = MemorySessionStore(nil)
        #expect(await store.loadSession() == .signedOut)
        await store.write(data)
        #expect(await store.loadSession() == .signedIn(accountID: "account"))
        #expect(await store.deletes == 0)
    }

    @Test(arguments: [
        "", "null", "[]", "{}", "{bad", #"{"token":"a"}"#,
        #"{"token":12,"accountId":"a"}"#, #"{"token":"","accountId":"a"}"#,
        #"{"token":"a","accountId":"  "}"#, #"{"token":"a","accountID":"a"}"#,
    ])
    func malformedSessionsAreDeletedAndSignedOut(_ json: String) async {
        let store = MemorySessionStore(Data(json.utf8))
        #expect(await store.loadSession() == .signedOut)
        #expect(await store.deletes == 1)
        #expect(await store.read() == nil)
        #expect(await store.loadSession() == .signedOut)
        #expect(await store.deletes == 1)
    }
}
