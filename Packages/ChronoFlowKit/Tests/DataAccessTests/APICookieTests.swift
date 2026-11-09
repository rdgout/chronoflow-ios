#if os(macOS)
    import AppCore
    import Foundation
    import Testing

    @testable import DataAccess

    @Suite(.timeLimit(.minutes(1))) struct APICookieTests {
        @Test func realRedirectCookieHandlingIsDisabled() async throws {
            let server = try LoopbackHTTPServer()
            defer { server.stop() }
            let baseURL = try await server.start()
            let redirectURL = baseURL.appendingPathComponent("redirect")
            let controlConfiguration = URLSessionConfiguration.ephemeral
            controlConfiguration.connectionProxyDictionary = [:]
            let control = URLSession(configuration: controlConfiguration)
            defer { control.invalidateAndCancel() }
            let (_, response) = try await control.data(from: redirectURL)
            #expect((response as? HTTPURLResponse)?.statusCode == 204)
            #expect(server.requests.count == 2)
            #expect(server.requests.last?.contains("redirect=fake") == true)
            #expect(control.configuration.httpCookieStorage?.cookies?.contains { $0.name == "redirect" } == true)

            let configuration = URLSessionConfiguration.ephemeral
            configuration.connectionProxyDictionary = [:]
            let storage = try #require(configuration.httpCookieStorage)
            storage.setCookie(
                try #require(
                    HTTPCookie(properties: [
                        .domain: "127.0.0.1", .path: "/", .name: "seed", .value: "fake",
                    ])))
            let client = APIClient(
                baseURL: try APIBaseURL(baseURL.absoluteString, release: false), configuration: configuration,
                bearer: { "artificial-old-token" })
            await #expect(throws: DataFailure.server(status: 302)) {
                try await client.requestNoContent(APIEndpoint(path: ["redirect"]))
            }
            #expect(server.requests.count == 3)
            try await client.requestNoContent(APIEndpoint(path: ["probe"]))
            #expect(server.requests.count == 4)
            for request in server.requests.suffix(2) {
                #expect(!request.lowercased().contains("\r\ncookie:"))
                #expect(request.lowercased().contains("authorization: bearer artificial-old-token"))
            }
            #expect(storage.cookies?.contains { $0.name == "redirect" } == false)
            #expect(await client.effectiveConfiguration.httpCookieStorage == nil)
        }
    }
#endif
