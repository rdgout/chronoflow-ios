import AppCore
import Foundation

public actor APIClient {
    public typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    private let baseURL: APIBaseURL
    private let configuration: URLSessionConfiguration
    private let bearer: @Sendable () async throws -> String?
    private let sleep: Sleep
    private let now: @Sendable () -> Date
    private var session: URLSession?

    var effectiveConfiguration: URLSessionConfiguration {
        session?.configuration ?? configuration.copy() as! URLSessionConfiguration
    }

    public init(
        baseURL: APIBaseURL, configuration: URLSessionConfiguration = .ephemeral,
        bearer: @escaping @Sendable () async throws -> String? = { nil },
        sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCredentialStorage = nil
        config.httpAdditionalHeaders = nil
        self.configuration = config
        self.bearer = bearer
        self.sleep = sleep
        self.now = now
    }

    public func request<Value: Decodable & Sendable>(
        _ endpoint: APIEndpoint, as: Value.Type = Value.self, expectedStatus: Int = 200
    ) async throws
        -> Value
    {
        let (data, response) = try await perform(endpoint)
        guard response.statusCode == expectedStatus else { throw DataFailure.server(status: response.statusCode) }
        do { return try JSONDecoder().decode(Value.self, from: data) } catch {
            throw DataFailure.server(status: response.statusCode)
        }
    }

    public func requestData(_ endpoint: APIEndpoint) async throws -> Data {
        let (data, response) = try await perform(endpoint)
        guard response.statusCode == 200 else { throw DataFailure.server(status: response.statusCode) }
        return data
    }

    public func requestNoContent(_ endpoint: APIEndpoint) async throws {
        let (data, response) = try await perform(endpoint)
        guard response.statusCode == 204, data.isEmpty else { throw DataFailure.server(status: response.statusCode) }
    }

    private func perform(_ endpoint: APIEndpoint) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        var request = URLRequest(url: try endpoint.url(relativeTo: baseURL), cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = endpoint.method
        request.httpBody = endpoint.body
        request.timeoutInterval = endpoint.timeout
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if endpoint.access == .authenticated {
            if let token = try await bearer(), !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                throw DataFailure.unauthorized(status: 401)
            }
        }
        try Task.checkCancellation()
        if session == nil {
            session = URLSession(configuration: configuration, delegate: APIRedirectDelegate(), delegateQueue: nil)
        }
        let session = session!
        let outgoingRequest = request
        let deadline = endpoint.timeout
        let sleeper = sleep
        let result: (Data, URLResponse)
        do {
            result = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask { [session, outgoingRequest] in try await session.data(for: outgoingRequest) }
                group.addTask { [sleeper, deadline] in
                    try await sleeper(deadline)
                    try Task.checkCancellation()
                    throw DataFailure.offline
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if let failure = error as? DataFailure { throw failure }
            throw DataFailure.offline
        }
        try Task.checkCancellation()
        guard let response = result.1 as? HTTPURLResponse else { throw DataFailure.server(status: nil) }
        guard (200..<300).contains(response.statusCode) else { throw mapError(result.0, response: response) }
        return (result.0, response)
    }

    private struct RetryHint: Decodable { let retryAfterSeconds: JSONValue? }

    private struct ErrorEnvelope: Decodable {
        let code: String
        let message: String
        let errors: [String: String]?
        let args: [String: [String: JSONValue]]?
        let retryAfterSeconds: JSONValue?
    }

    private func mapError(_ data: Data, response: HTTPURLResponse) -> DataFailure {
        let status = response.statusCode
        let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        if status == 429 {
            let body: Double?
            if case .number(let value) = (try? JSONDecoder().decode(RetryHint.self, from: data))?.retryAfterSeconds {
                let seconds = NSDecimalNumber(decimal: value).doubleValue
                body = seconds.isFinite && seconds >= 0 ? seconds : nil
            } else {
                body = nil
            }
            return .throttled(
                retryAfterSeconds: body ?? retryAfter(response.value(forHTTPHeaderField: "Retry-After")) ?? 60,
                status: status)
        }
        guard let envelope = decoded else {
            return .server(status: status)
        }
        switch (status, envelope.code) {
        case (401, "unauthenticated"): return .unauthorized(status: status)
        case (403, "email_unverified"): return .emailUnverified(status: status)
        case (422, "review_expired"): return .reviewExpired
        case (422, "validation_failed"):
            guard let errors = envelope.errors, !errors.isEmpty,
                errors.allSatisfy({ !$0.key.isEmpty && !$0.value.isEmpty }),
                (envelope.args ?? [:]).values.allSatisfy({
                    $0.values.allSatisfy { value in
                        switch value {
                        case .string, .number: true
                        default: false
                        }
                    }
                })
            else { return .server(status: status) }
            var fields: [String: FieldMessage] = [:]
            for (field, key) in errors {
                fields[field] = FieldMessage(key: key, arguments: envelope.args?[field] ?? [:])
            }
            return .validation(fields: fields, status: status)
        case (409, "conflict"): return .conflict(status: status)
        default: return .server(status: status)
        }
    }

    private func retryAfter(_ header: String?) -> TimeInterval? {
        guard let header else { return nil }
        if let seconds = Double(header), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: header).map { max(0, $0.timeIntervalSince(now())) }
    }
    deinit { session?.invalidateAndCancel() }
}
