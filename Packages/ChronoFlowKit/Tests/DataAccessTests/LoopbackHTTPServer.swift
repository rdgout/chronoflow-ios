#if os(macOS)
    import Foundation
    import Network

    final class LoopbackHTTPServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "DataAccessTests.loopback")
        private let lock = NSLock()
        private var received: [String] = []
        private var connections: [NWConnection] = []

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            listener = try NWListener(using: parameters)
        }

        var requests: [String] { lock.withLock { received } }

        func start() async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { [self] state in
                    switch state {
                    case .ready:
                        listener.stateUpdateHandler = nil
                        continuation.resume(returning: URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/v1")!)
                    case .failed(let error):
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    default: break
                    }
                }
                listener.newConnectionHandler = { [self] connection in
                    lock.withLock { connections.append(connection) }
                    connection.start(queue: queue)
                    receive(connection, buffered: Data())
                }
                listener.start(queue: queue)
            }
        }

        private func receive(_ connection: NWConnection, buffered: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [self] data, _, complete, error in
                let bytes = buffered + (data ?? Data())
                if let end = bytes.range(of: Data("\r\n\r\n".utf8)) {
                    let request = String(decoding: bytes[..<end.lowerBound], as: UTF8.self)
                    lock.withLock { received.append(request) }
                    let redirect = request.hasPrefix("GET /v1/redirect ")
                    let headers =
                        redirect
                        ? "302 Found\r\nLocation: /v1/next\r\nSet-Cookie: redirect=fake; Path=/\r\n"
                        : "204 No Content\r\n"
                    let reply = "HTTP/1.1 \(headers)Content-Length: 0\r\nConnection: close\r\n\r\n"
                    connection.send(
                        content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
                } else if complete || error != nil || bytes.count > 16_384 {
                    connection.cancel()
                } else {
                    receive(connection, buffered: bytes)
                }
            }
        }

        func stop() {
            listener.cancel()
            let pending = lock.withLock { connections }
            for connection in pending { connection.cancel() }
            listener.newConnectionHandler = nil
        }
    }
#endif
