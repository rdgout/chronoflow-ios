import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite(.timeLimit(.minutes(1))) struct APIClientTests {
    @Test(arguments: [
        ("unauthenticated", 401), ("email_unverified", 403), ("conflict", 409), ("forbidden", 403), ("not_found", 404),
        ("method_not_allowed", 405), ("payload_too_large", 413), ("unavailable", 503), ("server_error", 500),
        ("http_error", 418),
    ])
    func errors(code: String, status: Int) async throws {
        let body = try fixtureText("errors/\(code).json")
        let server = StubServer { _ in .init(status, body) }
        let client = try server.client()
        do {
            let _: AccountIdentity = try await client.request(APIEndpoint(path: ["users", "me"]))
            Issue.record("Expected error")
        } catch let failure as DataFailure {
            #expect(failure.status == status)
            switch code {
            case "unauthenticated": #expect(failure == .unauthorized(status: status))
            case "email_unverified": #expect(failure == .emailUnverified(status: status))
            case "conflict": #expect(failure == .conflict(status: status))
            default: #expect(failure == .server(status: status))
            }
        }
    }
    @Test func fieldArguments() async throws {
        let body = try fixtureText("errors/validation_failed.json")
        let server = StubServer { _ in .init(422, body) }
        let client = try server.client()
        do {
            let _: AccountIdentity = try await client.request(APIEndpoint(path: ["users", "me"]))
            Issue.record("Expected error")
        } catch let failure as DataFailure {
            #expect(
                failure
                    == .validation(
                        fields: [
                            "password": FieldMessage(
                                key: "Use no more than :max characters.", arguments: ["max": .number(255)])
                        ], status: 422))
        }
    }
    @Test(arguments: [
        "{}", "<html>Error</html>", #"{"code":"validation_failed","message":"bad"}"#,
        #"{"code":"validation_failed","message":"bad","errors":{}}"#,
        #"{"code":"validation_failed","message":"bad","errors":{"a":[]}}"#,
        #"{"code":"validation_failed","message":"bad","errors":{"a":"x"},"args":{"a":{"max":null}}}"#,
    ])
    func malformedErrors(body: String) async throws {
        let server = StubServer { _ in .init(422, body) }
        let client = try server.client()
        await #expect(throws: DataFailure.server(status: 422)) {
            let _: AccountIdentity = try await client.request(APIEndpoint(path: ["users", "me"]))
        }
    }
    @Test(arguments: ["{}", "<html>OK</html>", #"{"kind":"session","token":"fake"}"#])
    func malformedSuccess(body: String) async throws {
        let server = StubServer { _ in .init(200, body) }
        let source = APIDataSource(client: try server.client())
        await #expect(throws: DataFailure.server(status: 200)) {
            try await source.signIn(PasswordSignInInput(email: "x", password: "x", deviceID: "x", deviceName: "x"))
        }
    }
    @Test(arguments: [
        (#""retryAfterSeconds":37,"#, "12", 37.0), ("", "12", 12), ("", "Thu, 01 Jan 1970 00:02:00 GMT", 120),
        ("", "bad", 60), (#""retryAfterSeconds":-1,"#, "23", 23),
    ])
    func retryAfter(bodyMember: String, header: String, expected: Double) async throws {
        let server = StubServer { _ in
            .init(429, "{\(bodyMember)\"code\":\"throttled\",\"message\":\"fake\"}", headers: ["Retry-After": header])
        }
        let client = try server.client(now: { Date(timeIntervalSince1970: 0) })
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: expected, status: 429)) {
            let _: AccountIdentity = try await client.request(APIEndpoint(path: ["users", "me"]))
        }
    }
    @Test(arguments: [301, 302, 307, 308]) func refusesEveryRedirect(status: Int) async throws {
        for target in ["https://same.invalid/v1/next", "https://foreign.invalid/secret"] {
            let server = StubServer { _ in .init(status, "", headers: ["Location": target]) }
            let client = try server.client()
            await #expect(throws: DataFailure.server(status: status)) {
                let _: AccountIdentity = try await client.request(APIEndpoint(path: ["users", "me"]))
            }
            #expect(server.requests.count == 1)
            let delegate = APIRedirectDelegate()
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let request = URLRequest(url: URL(string: target)!)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            let allowed = await withCheckedContinuation { continuation in
                delegate.urlSession(
                    session, task: session.dataTask(with: request), willPerformHTTPRedirection: response,
                    newRequest: request
                ) { continuation.resume(returning: $0 != nil) }
            }
            #expect(!allowed)
        }
    }
    @Test func transportAndExplicitCancellation() async throws {
        let failed = StubServer { _ in .init(error: URLError(.timedOut)) }
        let client = try failed.client()
        await #expect(throws: DataFailure.offline) {
            let _: AccountIdentity = try await client.request(APIEndpoint(path: ["users", "me"]))
        }
        let blocked = StubServer { _ in .init(hold: true) }
        let held = try blocked.client()
        let task = Task { let _: AccountIdentity = try await held.request(APIEndpoint(path: ["users", "me"])) }
        await blocked.started.wait()
        #expect(blocked.requests.count == 1)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        await blocked.stopped.wait()
        #expect(blocked.stopCount == 1)
    }
    @Test(arguments: [3.0, 15.0, 90.0]) func deadlinesCancelUnderlyingTask(seconds: Double) async throws {
        let blocked = StubServer { _ in .init(hold: true) }
        let client = try blocked.client(sleep: { deadline in
            #expect(deadline == seconds)
            await blocked.started.wait()
        })
        await #expect(throws: DataFailure.offline) {
            let _: AccountIdentity = try await client.request(APIEndpoint(path: ["users", "me"], timeout: seconds))
        }
        await blocked.stopped.wait()
        #expect(blocked.stopCount == 1)
    }
    @Test func noCookieOrCacheReuseAndMissingBearer() async throws {
        let body = try fixtureText("account/identity.json")
        let server = StubServer { request in
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
            return .init(200, body, headers: ["Set-Cookie": "secret=fake", "Cache-Control": "max-age=3600"])
        }
        let client = try server.client()
        let _: AccountIdentity = try await client.request(APIEndpoint(path: ["users", "me"]))
        let _: AccountIdentity = try await client.request(APIEndpoint(path: ["users", "me"]))
        #expect(server.requests.count == 2)
        let empty = APIClient(baseURL: try APIBaseURL("https://never.invalid/v1", release: true))
        await #expect(throws: DataFailure.unauthorized(status: 401)) {
            let _: AccountIdentity = try await empty.request(APIEndpoint(path: ["users", "me"]))
        }
    }
}

extension APIClientTests {
    @Test(arguments: [(200, "{}"), (201, "{}"), (204, "{}")]) func noContentRequiresExactShape(
        status: Int, body: String
    ) async throws {
        let server = StubServer { _ in .init(status, body) }
        let client = try server.client()
        await #expect(throws: DataFailure.server(status: status)) {
            try await client.requestNoContent(APIEndpoint(method: "POST", path: ["auth", "logout"]))
        }
    }
}
