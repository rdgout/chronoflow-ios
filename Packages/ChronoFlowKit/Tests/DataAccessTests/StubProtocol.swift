import AppCore
import Foundation
import Testing

@testable import DataAccess

final class StubServer: @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var body = Data()
        var headers: [String: String] = [:]
        var error: URLError?
        var hold = false
        init(
            _ status: Int = 200, _ text: String = "", headers: [String: String] = [:], error: URLError? = nil,
            hold: Bool = false
        ) {
            self.status = status
            body = Data(text.utf8)
            self.headers = headers
            self.error = error
            self.hold = hold
        }
    }
    private let lock = NSLock()
    private var received: [URLRequest] = []
    private var stops = 0
    let started = StubSignal()
    let stopped = StubSignal()
    let handler: @Sendable (URLRequest) throws -> Reply
    let host = UUID().uuidString.lowercased() + ".invalid"
    init(_ handler: @escaping @Sendable (URLRequest) throws -> Reply) { self.handler = handler }
    func record(_ request: URLRequest) {
        lock.withLock { received.append(request) }
        started.fire()
    }
    func stop() {
        lock.withLock { stops += 1 }
        stopped.fire()
    }
    var requests: [URLRequest] { lock.withLock { received } }
    var stopCount: Int { lock.withLock { stops } }
    func client(
        sleep: @escaping APIClient.Sleep = { _ in
            let pair = AsyncStream<Void>.makeStream()
            var iterator = pair.stream.makeAsyncIterator()
            _ = await iterator.next()
            try Task.checkCancellation()
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> APIClient {
        StubProtocol.registry.install(self)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(
            baseURL: try APIBaseURL("https://\(host)/v1", release: true), configuration: config,
            bearer: { "artificial-old-token" }, sleep: sleep, now: now)
    }
    deinit { StubProtocol.registry.remove(host) }
}

final class StubRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var servers: [String: WeakStubServer] = [:]
    func install(_ server: StubServer) { lock.withLock { servers[server.host] = WeakStubServer(server) } }
    func remove(_ host: String) { lock.withLock { _ = servers.removeValue(forKey: host) } }
    func server(_ host: String) -> StubServer? { lock.withLock { servers[host]?.value } }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let registry = StubRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let server = Self.registry.server(request.url?.host ?? "") else {
            Issue.record("Unmatched request denied")
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        server.record(request)
        do {
            let reply = try server.handler(request)
            if reply.hold { return }
            if let error = reply.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { Self.registry.server(request.url?.host ?? "")?.stop() }
}

func fixture(_ path: String) throws -> Data {
    let url = Bundle.module.resourceURL!.appendingPathComponent("\(path)")
    return try Data(contentsOf: url)
}
func fixtureText(_ path: String) throws -> String { String(decoding: try fixture(path), as: UTF8.self) }
func requestJSON(_ request: URLRequest) throws -> JSONObject {
    let data: Data
    if let body = request.httpBody {
        data = body
    } else if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            output.append(contentsOf: buffer.prefix(n))
        }
        data = output
    } else {
        data = Data()
    }
    return try JSONDecoder().decode(JSONObject.self, from: data)
}

private final class WeakStubServer {
    weak var value: StubServer?
    init(_ value: StubServer) { self.value = value }
}

final class StubSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func fire() {
        let pending = lock.withLock {
            let values = waiters
            waiters = []
            fired = true
            return values
        }
        for waiter in pending { waiter.resume() }
    }
    func wait() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if fired { return true }
                waiters.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }
}
