import AppCore
import DataAccess
import Foundation
import LocalStore
import Sync
import Testing

@Suite struct DataSourceIntegrationTests {
    @Test func mockServerAbsoluteReplayAndOfflineRestart() async throws {
        let store = try await SyncStore()
        let serverState = MemoryMockStateStore()
        let source = MockDataSource(
            store: serverState,
            seed: MockServerState(
                accounts: [
                    MockServerAccount(
                        snapshot: snapshot(), password: "fixture-password",
                        trips: [card()], details: [syncTrip: detail()])
                ], signingKey: Data("fixture-signing-key".utf8)),
            now: { syncDate }, sleep: { _ in }, id: { syncOther })
        _ = try await source.signIn(
            PasswordSignInInput(
                email: "demo@example.com", password: "fixture-password", deviceID: syncOther, deviceName: "Test"))
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        #expect(try await engine.refreshNow().state == .idle)
        let row = try await store.enqueue(.checkOff(check()))
        let accepted = try await source.send(row.change)
        #expect(try await source.send(row.change) == accepted)
        #expect(try await engine.refreshNow().pendingCount == 0)
        #expect(
            try await TripRepository(database: store.database).checks(tripID: syncTrip, inputHash: "hash").count == 1)
        await source.setOffline(true)
        _ = try await store.enqueue(
            .settings(section: .preferences, patch: JSONObject(["time_format": .string("12")])), index: 1)
        #expect(try await engine.refreshNow().state == .offline)
        await engine.cancelAndWait()
        try await store.database.close()
        try await store.database.open(accountID: syncAccount)
        let restored = try await SettingsRepository(database: store.database).settings()
        #expect(
            try restored.first { $0.section == "preferences" }?.value.decode(JSONObject.self)["timeFormat"]
                == .string("12"))
        #expect(try await OutboxRepository(database: store.database).pending().count == 1)
        try await store.close()
    }

    @Test func apiSourcePullAndOutboxThroughDenyByDefaultProtocol() async throws {
        let store = try await SyncStore()
        let server = SyncHTTPServer(replies: [
            "/v1/users/me": try JSONEncoder().encode(identity()),
            "/v1/account": try JSONEncoder().encode(snapshot()),
            "/v1/trips": try JSONEncoder().encode(["trips": [card()]]),
            "/v1/trips/\(syncTrip)": try JSONEncoder().encode(detail()),
        ])
        SyncHTTPProtocol.registry.install(server)
        defer { SyncHTTPProtocol.registry.remove(server.host) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncHTTPProtocol.self]
        let client = APIClient(
            baseURL: try APIBaseURL("https://\(server.host)/v1", release: true),
            configuration: configuration, bearer: { "fixture-bearer" },
            sleep: { _ in
                let (stream, _) = AsyncStream<Void>.makeStream()
                var iterator = stream.makeAsyncIterator()
                _ = await iterator.next()
                try Task.checkCancellation()
            })
        let engine = SyncEngine(database: store.database, source: APIDataSource(client: client), epoch: store.epoch)
        _ = try await store.enqueue(.walkthrough)
        #expect(try await engine.refreshNow().state == .idle)
        #expect(
            server.requests.map { $0.httpMethod! + " " + $0.url!.path } == [
                "POST /v1/walkthrough", "GET /v1/users/me", "GET /v1/account", "GET /v1/trips",
                "GET /v1/trips/\(syncTrip)",
            ])
        #expect(server.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-bearer" })
        #expect(try await AccountRepository(database: store.database).account()?.syncedAt != nil)
        #expect(try await OutboxRepository(database: store.database).pending().isEmpty)
        await engine.cancelAndWait()
        try await store.close()
    }
}

private final class SyncHTTPServer: @unchecked Sendable {
    let host = UUID().uuidString.lowercased() + ".invalid"
    let replies: [String: Data]
    private let lock = NSLock()
    private var received: [URLRequest] = []
    init(replies: [String: Data]) { self.replies = replies }
    func receive(_ request: URLRequest) { lock.withLock { received.append(request) } }
    var requests: [URLRequest] { lock.withLock { received } }
}
private final class SyncHTTPRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var servers: [String: SyncHTTPServer] = [:]
    func install(_ server: SyncHTTPServer) { lock.withLock { servers[server.host] = server } }
    func remove(_ host: String) { _ = lock.withLock { servers.removeValue(forKey: host) } }
    func server(_ host: String) -> SyncHTTPServer? { lock.withLock { servers[host] } }
}
private final class SyncHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let registry = SyncHTTPRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let server = Self.registry.server(request.url?.host ?? "") else {
            Issue.record("Unmatched sync request denied")
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        server.receive(request)
        let status: Int
        let body: Data
        if request.httpMethod == "POST", request.url?.path == "/v1/walkthrough" {
            status = 204
            body = Data()
        } else if request.httpMethod == "GET", let data = server.replies[request.url?.path ?? ""] {
            status = 200
            body = data
        } else {
            Issue.record("Unmatched sync route denied")
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
