import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct PasskeyManagementAPITests {
    private let attestation = ApiPasskeyAttestation(
        id: "AQID", rawId: "AQID",
        response: ApiPasskeyAttestationResponse(
            clientDataJSON: "Y2Q", attestationObject: "YXR0", transports: ["internal"]))

    @Test func everyPasskeyRouteUsesThePhase20MethodPathBodyAndStatus() async throws {
        let server = StubServer { request in
            switch (request.httpMethod!, request.url!.path) {
            case ("GET", "/v1/account/passkeys"):
                #expect(
                    request.httpBody == nil
                        && request.value(forHTTPHeaderField: "Authorization") == "Bearer artificial-old-token")
                return .init(
                    200,
                    #"{"passkeys":[{"id":1,"name":"iPhone","authenticator":"Apple Passwords","createdAt":"2026-10-02T10:00:00.000000Z","lastUsedAt":null}]}"#
                )
            case ("POST", "/v1/account/passkeys/options"):
                #expect(try requestJSON(request).fields == ["current_password": .string("pw")])
                return .init(
                    200,
                    #"{"challengeId":"c1","options":{"challenge":"Y2g","timeout":60000,"rp":{"id":"app.chronoflow.net","name":"app.chronoflow.net"},"user":{"id":"dQ","name":"n","displayName":"N"},"pubKeyCredParams":[{"type":"public-key","alg":-7},{"type":"public-key","alg":-257}],"authenticatorSelection":{"requireResidentKey":true,"userVerification":"required","residentKey":"required"},"attestation":"none","excludeCredentials":[{"type":"public-key","id":"AQID"}]}}"#
                )
            case ("POST", "/v1/account/passkeys"):
                let body = try requestJSON(request)
                #expect(body["challengeId"] == .string("c1") && body["name"] == .string("iPhone"))
                #expect(body["current_password"] == nil && body["credential"]?.object?["rawId"] == .string("AQID"))
                return .init(
                    201,
                    #"{"id":12,"name":"iPhone","authenticator":"Apple Passwords","createdAt":"2026-11-12T09:30:00.000000Z","lastUsedAt":null}"#
                )
            case ("DELETE", "/v1/account/passkeys/12"):
                #expect(try requestJSON(request).fields == ["current_password": .string("pw")])
                return .init(204)
            default:
                Issue.record("Unexpected passkey route \(request.httpMethod!) \(request.url!.path)")
                return .init(500)
            }
        }
        let source = APIDataSource(client: try server.client())
        #expect(
            try await source.accountSecurity(.listPasskeys)
                == .passkeys([
                    ApiPasskey(
                        id: 1, name: "iPhone", authenticator: "Apple Passwords",
                        createdAt: "2026-10-02T10:00:00.000000Z")
                ]))
        guard
            case .passkeyCreation(let challenge) = try await source.accountSecurity(
                .passkeyCreationOptions(current: "pw"))
        else {
            Issue.record("Expected creation options")
            return
        }
        #expect(challenge.challengeId == "c1" && challenge.options.excludeCredentials.map(\.id) == ["AQID"])
        let input = ApiPasskeyRegistrationInput(challengeId: "c1", name: "iPhone", credential: attestation)
        #expect(
            try await source.accountSecurity(.addPasskey(input))
                == .passkeyAdded(
                    ApiPasskey(
                        id: 12, name: "iPhone", authenticator: "Apple Passwords",
                        createdAt: "2026-11-12T09:30:00.000000Z")))
        #expect(try await source.accountSecurity(.removePasskey(id: 12, current: "pw")) == .changed)
    }

    @Test func storeAnsweringAnythingButCreatedIsAFailure() async throws {
        let server = StubServer { _ in
            .init(200, #"{"id":12,"name":"iPhone","createdAt":"2026-11-12T09:30:00.000000Z","lastUsedAt":null}"#)
        }
        let source = APIDataSource(client: try server.client())
        let input = ApiPasskeyRegistrationInput(challengeId: "c1", name: "iPhone", credential: attestation)
        await #expect(throws: DataFailure.server(status: 200)) { try await source.accountSecurity(.addPasskey(input)) }
    }

    @Test func validationAndThrottleErrorsKeepTheirMapping() async throws {
        let server = StubServer { request in
            if request.httpMethod == "DELETE" {
                return .init(
                    422,
                    #"{"code":"validation_failed","message":"The given data was invalid.","errors":{"current_password":"The provided password was incorrect."}}"#
                )
            }
            return .init(
                429, #"{"code":"throttled","message":"Slow down.","retryAfterSeconds":30}"#,
                headers: ["Retry-After": "30"])
        }
        let source = APIDataSource(client: try server.client())
        let wrong = await failure { try await source.accountSecurity(.removePasskey(id: 1, current: "bad")) }
        guard case .validation(let fields, 422)? = wrong else {
            Issue.record("Expected validation, got \(String(describing: wrong))")
            return
        }
        #expect(fields["current_password"]?.key == "The provided password was incorrect.")
        let limited = await failure { try await source.accountSecurity(.passkeyCreationOptions(current: "pw")) }
        #expect(limited == .throttled(retryAfterSeconds: 30, status: 429))
    }

    private func failure(_ body: () async throws -> AccountSecurityResult) async -> DataFailure? {
        do { _ = try await body() } catch { return error as? DataFailure }
        return nil
    }
}
