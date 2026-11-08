import Foundation

public struct ResetPasswordLink: Hashable, Sendable {
    public let token: String
    public let email: String
    public init(token: String, email: String) {
        self.token = token
        self.email = email
    }
    public var isValid: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum AuthLink: Hashable, Sendable {
    case reset(ResetPasswordLink)
    case verify(SignedVerificationInput?)

    public init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme == "https", parts.host == "app.chronoflow.net", parts.port == nil,
            parts.user == nil, parts.password == nil, parts.fragment == nil
        else { return nil }
        let path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        if path.count >= 3, path[1] == "email", path[2] == "verify" {
            let items = parts.queryItems ?? []
            let expires = items.filter { $0.name == "expires" }
            let signature = items.filter { $0.name == "signature" }
            func hex(_ value: String, count: Int) -> Bool {
                value.count == count
                    && value.utf8.allSatisfy {
                        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                    }
            }
            guard path.count == 5,
                let id = String(path[3]).removingPercentEncoding, UUID(uuidString: id) != nil,
                let hash = String(path[4]).removingPercentEncoding, hex(hash, count: 40),
                items.count == 2, expires.count == 1, signature.count == 1,
                let seconds = expires[0].value, !seconds.isEmpty, seconds.utf8.allSatisfy({ (48...57).contains($0) }),
                let expiration = Int(seconds), let signed = signature[0].value, hex(signed, count: 64)
            else {
                self = .verify(nil)
                return
            }
            self = .verify(SignedVerificationInput(id: id, hash: hash, expires: expiration, signature: signed))
            return
        }
        guard path.count >= 2, path[1] == "reset-password" else { return nil }
        let items = parts.queryItems ?? []
        let email = items.filter { $0.name == "email" }
        let valid = path.count == 3 && !path[2].isEmpty && email.count == 1 && items.count == 1
        self = .reset(
            ResetPasswordLink(
                token: valid ? String(path[2]).removingPercentEncoding ?? "" : "",
                email: email.count == 1 ? email[0].value ?? "" : ""))
    }
}
