import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct AccountSecurityAPITests {
    @Test func everySecurityRouteUsesTheRealMethodAndBody() async throws {
        let server = StubServer { request in
            let body = try requestJSON(request).fields.compactMapValues(\.string)
            switch request.url!.path {
            case "/v1/auth/forgot-password":
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(body == ["email": "demo@example.com"])
                return .init(204)
            case "/v1/account/password":
                #expect(request.httpMethod == "PUT")
                #expect(body == ["current_password": "old", "password": "new", "password_confirmation": "new"])
                return .init(204)
            case "/v1/account/two-factor/confirmation":
                #expect(request.httpMethod == "POST" && body == ["code": "123456"])
                return .init(200, "{\"recoveryCodes\":[\"code\"]}")
            case "/v1/account/two-factor":
                #expect(body == ["current_password": "old"])
                if request.httpMethod == "DELETE" { return .init(200, try fixtureText("account/snapshot.json")) }
                #expect(request.httpMethod == "POST")
                return .init(200, "{\"secretKey\":\"secret\",\"otpauthUrl\":\"otpauth://test\"}")
            case "/v1/account/two-factor/recovery-codes", "/v1/account/two-factor/recovery-codes/reveal":
                #expect(request.httpMethod == "POST" && body == ["current_password": "old"])
                return .init(200, "{\"recoveryCodes\":[\"code\"]}")
            default:
                Issue.record("Unexpected security route")
                return .init(500)
            }
        }
        let source = APIDataSource(client: try server.client())
        #expect(try await source.accountSecurity(.requestPasswordReset(email: "demo@example.com")) == .changed)
        #expect(
            try await source.accountSecurity(.password(current: "old", password: "new", confirmation: "new"))
                == .changed)
        #expect(
            try await source.accountSecurity(.enableTwoFactor(current: "old"))
                == .setup(ApiTwoFactorSetup(secretKey: "secret", otpauthUrl: "otpauth://test")))
        for action in [
            AccountSecurityChange.confirmTwoFactor(code: "123456"), .revealRecoveryCodes(current: "old"),
            .regenerateRecoveryCodes(current: "old"),
        ] {
            #expect(try await source.accountSecurity(action) == .codes(ApiRecoveryCodes(recoveryCodes: ["code"])))
        }
        if case .snapshot = try await source.accountSecurity(.disableTwoFactor(current: "old")) {
        } else {
            Issue.record("Expected account snapshot")
        }
    }

    @Test func backendConflictKeysSurviveErrorMapping() async throws {
        for key in [
            "Two-factor authentication is already on.", "Two-factor authentication is off.",
            "Start two-factor setup again.",
        ] {
            let server = StubServer { _ in .init(409, "{\"code\":\"conflict\",\"message\":\"\(key)\"}") }
            let source = APIDataSource(client: try server.client())
            await #expect(throws: DataFailure.validation(fields: ["form": FieldMessage(key: key)], status: 409)) {
                try await source.accountSecurity(.enableTwoFactor(current: "password"))
            }
        }
    }

    @Test func mockRunsSetupCodesManageAndPasswordAndRejectsOffline() async throws {
        let source = try mockSource()
        _ = try await login(source)
        await #expect(
            throws: DataFailure.validation(
                fields: ["current_password": FieldMessage(key: "The provided password was incorrect.")], status: 422)
        ) {
            try await source.accountSecurity(.enableTwoFactor(current: "wrong"))
        }
        if case .setup = try await source.accountSecurity(.enableTwoFactor(current: "password")) {
        } else {
            Issue.record("Expected setup")
        }
        if case .codes(let value) = try await source.accountSecurity(.confirmTwoFactor(code: "123456")) {
            #expect(value.recoveryCodes.count == 8)
        } else {
            Issue.record("Expected codes")
        }
        #expect(try await source.fetchAccount().security["twoFactorEnabled"] == .bool(true))
        _ = try await source.accountSecurity(.revealRecoveryCodes(current: "password"))
        _ = try await source.accountSecurity(.regenerateRecoveryCodes(current: "password"))
        _ = try await source.accountSecurity(.disableTwoFactor(current: "password"))
        #expect(try await source.fetchAccount().security["twoFactorEnabled"] == .bool(false))
        #expect(try await source.fetchAccount().security["twoFactorConfirmedAt"] == .null)
        _ = try await source.accountSecurity(
            .password(current: "password", password: "New password1!", confirmation: "New password1!"))
        await source.setOffline(true)
        await #expect(throws: DataFailure.offline) {
            try await source.accountSecurity(.enableTwoFactor(current: "New password1!"))
        }
    }
}
