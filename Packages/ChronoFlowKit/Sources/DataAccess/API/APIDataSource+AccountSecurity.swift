import AppCore
import Foundation

extension APIDataSource {
    public func deleteAccount(password: String) async throws {
        try await client.requestNoContent(
            APIEndpoint(method: "DELETE", path: ["account"], body: JSONEncoder().encode(["password": password])))
    }

    public func accountSecurity(_ change: AccountSecurityChange) async throws -> AccountSecurityResult {
        func endpoint(_ method: String, _ path: [String], _ fields: [String: JSONValue]) throws -> APIEndpoint {
            APIEndpoint(method: method, path: ["account"] + path, body: try JSONEncoder().encode(JSONObject(fields)))
        }
        switch change {
        case .requestPasswordReset(let email):
            try await requestPasswordReset(email: email)
            return .changed
        case .password(let current, let password, let confirmation):
            try await client.requestNoContent(
                endpoint(
                    "PUT", ["password"],
                    [
                        "current_password": .string(current), "password": .string(password),
                        "password_confirmation": .string(confirmation),
                    ]))
            return .changed
        case .enableTwoFactor(let current):
            return .setup(
                try await client.request(endpoint("POST", ["two-factor"], ["current_password": .string(current)])))
        case .confirmTwoFactor(let code):
            return .codes(
                try await client.request(endpoint("POST", ["two-factor", "confirmation"], ["code": .string(code)])))
        case .disableTwoFactor(let current):
            return .snapshot(
                try await client.request(endpoint("DELETE", ["two-factor"], ["current_password": .string(current)])))
        case .revealRecoveryCodes(let current):
            return .codes(
                try await client.request(
                    endpoint(
                        "POST", ["two-factor", "recovery-codes", "reveal"], ["current_password": .string(current)])))
        case .regenerateRecoveryCodes(let current):
            return .codes(
                try await client.request(
                    endpoint("POST", ["two-factor", "recovery-codes"], ["current_password": .string(current)])))
        case .listPasskeys:
            let list: ApiPasskeyList = try await client.request(APIEndpoint(path: ["account", "passkeys"]))
            return .passkeys(list.passkeys)
        case .passkeyCreationOptions(let current):
            return .passkeyCreation(
                try await client.request(
                    endpoint("POST", ["passkeys", "options"], ["current_password": .string(current)])))
        case .addPasskey(let input):
            return .passkeyAdded(
                try await client.request(
                    APIEndpoint(method: "POST", path: ["account", "passkeys"], body: try JSONEncoder().encode(input)),
                    expectedStatus: 201))
        case .removePasskey(let id, let current):
            try await client.requestNoContent(
                endpoint("DELETE", ["passkeys", String(id)], ["current_password": .string(current)]))
            return .changed
        }
    }
}
