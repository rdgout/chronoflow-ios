import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct APIDataSourceTests {
    @Test func nativeLinkInputsReachExactPublicResetAndAuthenticatedSignedVerificationBodies() async throws {
        let id = "0199a3c0-0000-7000-8000-000000000001"
        let hash = String(repeating: "a", count: 40)
        let signature = String(repeating: "b", count: 64)
        let resetURL = try #require(
            URL(string: "https://app.chronoflow.net/reset-password/a%252Fb?email=a%2Bb%40example.com"))
        let verifyURL = try #require(
            URL(
                string:
                    "https://app.chronoflow.net/email/verify/\(id)/\(hash)?expires=1800000000&signature=\(signature)"))
        guard case .reset(let reset) = AuthLink(url: resetURL), case .verify(let signed?) = AuthLink(url: verifyURL)
        else {
            Issue.record("Link parsing failed")
            return
        }
        let verification = try fixtureText("auth/verification.json")
        let server = StubServer { request in
            let body = try requestJSON(request)
            if request.url?.path == "/v1/auth/reset-password" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(body["token"] == .string("a%2Fb") && body["email"] == .string("a+b@example.com"))
                #expect(
                    body["password"] == .string("NewPassword123!")
                        && body["password_confirmation"] == .string("NewPassword123!"))
                return .init(204)
            }
            #expect(request.url?.path == "/v1/email/verify")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer artificial-old-token")
            #expect(
                body
                    == JSONObject([
                        "id": .string(id), "hash": .string(hash), "expires": .number(1_800_000_000),
                        "signature": .string(signature),
                    ]))
            return .init(200, verification)
        }
        let source = APIDataSource(client: try server.client())
        try await source.resetPassword(
            ResetPasswordInput(
                token: reset.token, email: reset.email, password: "NewPassword123!",
                passwordConfirmation: "NewPassword123!"))
        _ = try await source.verifyEmail(signed)
        #expect(server.requests.count == 2)
    }

    @Test func publicAuthRoutesAndSignedVerification() async throws {
        let session = try fixtureText("auth/session.json")
        let twoFactor = try fixtureText("auth/two-factor.json")
        let options = try fixtureText("auth/passkey-options.json")
        let verification = try fixtureText("auth/verification.json")
        let server = StubServer { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            let path = request.url!.path
            if path.hasPrefix("/v1/auth/") && path != "/v1/auth/logout" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            } else {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer artificial-old-token")
            }
            if path == "/v1/auth/passkey/options" {
                #expect(request.httpBody == nil && request.httpBodyStream == nil)
                #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
                return .init(200, options)
            }
            if path == "/v1/auth/logout" {
                #expect(request.timeoutInterval == 3)
                return .init(204)
            }
            if path == "/v1/email/verification-notification" { return .init(200, verification) }
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try requestJSON(request)
            switch path {
            case "/v1/auth/login":
                #expect(body["device_id"]?.string == "test-device")
                return .init(200, twoFactor)
            case "/v1/auth/two-factor": #expect(body["code"]?.string == "123456" && body["recovery_code"] == nil)
            case "/v1/auth/register":
                #expect(request.timeoutInterval == 90)
                #expect(body["language"] == .string("nl"))
            case "/v1/auth/passkey/login": #expect(body["credential"]?.object?["rawId"] == .string("AA=="))
            case "/v1/auth/forgot-password", "/v1/auth/reset-password": return .init(204)
            case "/v1/email/verify":
                #expect(Set(body.fields.keys) == ["id", "hash", "expires", "signature"])
                return .init(200, verification)
            default: Issue.record("Unmatched route \(path)")
            }
            return .init(200, session)
        }
        let source = APIDataSource(client: try server.client())
        #expect(
            try await source.signIn(
                PasswordSignInInput(
                    email: "test@example.com", password: "fake", deviceID: "test-device", deviceName: "iPhone"))
                == .twoFactor(challengeId: "artificial-two-factor-challenge"))
        _ = try await source.completeTwoFactor(TwoFactorInput(challengeId: "fake", proof: .code("123456")))
        _ = try await source.signUp(
            RegisterInput(
                name: "Test", email: "test@example.com", password: "fake", passwordConfirmation: "fake",
                deviceID: "test-device", deviceName: "iPhone", language: .nl))
        _ = try await source.passkeyOptions()
        _ = try await source.passkeyLogin(
            ApiPasskeyLoginInput(
                challengeId: "fake",
                credential: ApiPasskeyAssertion(
                    id: "AA", rawId: "AA==",
                    response: ApiPasskeyAssertionResponse(
                        clientDataJSON: "AA", authenticatorData: "AA", signature: "AA")), deviceID: "test-device",
                deviceName: "iPhone"))
        try await source.requestPasswordReset(email: "test@example.com")
        try await source.resetPassword(
            ResetPasswordInput(
                token: "fake", email: "test@example.com", password: "fake", passwordConfirmation: "fake"))
        _ = try await source.resendVerificationEmail()
        _ = try await source.verifyEmail(
            SignedVerificationInput(id: "fake", hash: "fake", expires: 1, signature: "fake"))
        try await source.signOut()
        #expect(server.requests.count == 10)
    }
    @Test func protectedReadsMutationsAndPathEncoding() async throws {
        let identity = try fixtureText("account/identity.json")
        let account = try fixtureText("account/snapshot.json")
        let list = try fixtureText("trips/list.json")
        let detail = try fixtureText("trips/detail.json")
        let checks = try fixtureText("trips/checks.json")
        let server = StubServer { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer artificial-old-token")
            let path = request.url!.path
            switch (request.httpMethod!, path) {
            case ("GET", "/v1/users/me"), ("PATCH", "/v1/users/me"): return .init(200, identity)
            case ("GET", "/v1/account"), ("PATCH", "/v1/account/body-clock"), ("PATCH", "/v1/account/preferences"),
                ("PATCH", "/v1/account/reminders"):
                return .init(200, account)
            case ("GET", "/v1/trips"): return .init(200, list)
            case ("GET", "/v1/trips/0199a3c0-0000-7000-8000-000000000010"): return .init(200, detail)
            case ("PUT", "/v1/trips/test/checks"):
                let body = try requestJSON(request)
                #expect(body["tripID"] == nil && body["status"] == .null)
                return .init(200, checks)
            case ("POST", "/v1/terms/acceptance"):
                #expect(try requestJSON(request) == JSONObject(["accepted": .bool(true), "version": .string("1.0")]))
                return .init(204)
            case ("POST", "/v1/walkthrough"): return .init(204)
            default:
                Issue.record("Unmatched route")
                return .init(500)
            }
        }
        let source = APIDataSource(client: try server.client())
        _ = try await source.fetchIdentity()
        _ = try await source.verificationStatus()
        _ = try await source.fetchAccount()
        #expect(try await source.fetchTrips().count == 1)
        _ = try await source.fetchTripDetail(id: "0199a3c0-0000-7000-8000-000000000010")
        _ = try await source.send(
            .checkOff(
                CheckOffChange(
                    tripID: "test", planInputHash: "fake", type: .sleep, localDate: "2026-11-10", ordinal: 1,
                    status: nil)))
        for section in [SettingsSection.bodyClock, .preferences, .reminders] {
            let key = section == .bodyClock ? "habitual_bed" : section == .preferences ? "time_format" : "lead_min"
            _ = try await source.send(.settings(section: section, patch: JSONObject([key: .string("test")])))
        }
        _ = try await source.send(.profile(ProfileChange(name: "Test", email: "demo@example.com")))
        _ = try await source.send(.policies(version: "1.0"))
        _ = try await source.send(.walkthrough)
        await #expect(throws: DataFailure.unsupported(.security)) {
            try await source.send(.unsupported(kind: .security, payload: JSONObject()))
        }
        let base = try APIBaseURL("https://example.invalid/v1/", release: true)
        let url = try APIEndpoint(path: ["trips", "a/b?# %"]).url(relativeTo: base)
        #expect(url.absoluteString == "https://example.invalid/v1/trips/a%2Fb%3F%23%20%25")
        #expect(try APIEndpoint(path: ["trips", ".."]).url(relativeTo: base).absoluteString.hasSuffix("/%2E%2E"))
    }
    @Test func passkeyErrorsAndUnverified() async throws {
        let body = try fixtureText("auth/unverified.json")
        let server = StubServer { _ in .init(200, body) }
        let source = APIDataSource(client: try server.client())
        let input = ApiPasskeyLoginInput(
            challengeId: "fake",
            credential: ApiPasskeyAssertion(
                id: "AA", rawId: "AA==",
                response: ApiPasskeyAssertionResponse(clientDataJSON: "AA", authenticatorData: "AA", signature: "AA")),
            deviceID: "fake", deviceName: "iPhone")
        #expect(try await !source.passkeyLogin(input).account.hasVerifiedEmail)
        for (field, key) in [
            ("credential", "We couldn't sign you in with that passkey. Please try again."),
            ("challengeId", "The passkey request expired. Please try again."),
        ] {
            let errorBody = String(
                decoding: try JSONEncoder().encode(
                    JSONObject([
                        "code": .string("validation_failed"), "message": .string("The given data was invalid."),
                        "errors": .object([field: .string(key)]),
                    ])), as: UTF8.self)
            let failed = StubServer { _ in .init(422, errorBody) }
            let api = APIDataSource(client: try failed.client())
            await #expect(throws: DataFailure.validation(fields: [field: FieldMessage(key: key)], status: 422)) {
                try await api.passkeyLogin(input)
            }
        }
    }
}

extension APIDataSourceTests {
    @Test func rejectsInvalidPasskeyOptionsAndSessionDiscriminator() async throws {
        let options = try fixtureText("auth/passkey-options.json")
        for body in [
            options.replacingOccurrences(of: "app.chronoflow.net", with: "foreign.invalid"),
            options.replacingOccurrences(of: "60000", with: "120000"),
            options.replacingOccurrences(
                of: String(repeating: "A", count: 43), with: String(repeating: "+", count: 43)),
            options.replacingOccurrences(of: "required", with: "preferred"),
        ] {
            let server = StubServer { _ in .init(200, body) }
            let source = APIDataSource(client: try server.client())
            await #expect(throws: DataFailure.server(status: 200)) { try await source.passkeyOptions() }
        }
        let body = try fixtureText("auth/two-factor.json")
        let server = StubServer { _ in .init(200, body) }
        let source = APIDataSource(client: try server.client())
        await #expect(throws: DataFailure.server(status: 200)) {
            try await source.passkeyLogin(
                ApiPasskeyLoginInput(
                    challengeId: "fake",
                    credential: ApiPasskeyAssertion(
                        id: "AA", rawId: "AA==",
                        response: ApiPasskeyAssertionResponse(
                            clientDataJSON: "AA", authenticatorData: "AA", signature: "AA")), deviceID: "fake",
                    deviceName: "iPhone")
            )
        }
    }
}
