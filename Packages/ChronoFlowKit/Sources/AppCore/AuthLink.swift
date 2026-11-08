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

    public init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme == "https", parts.host == "app.chronoflow.net", parts.port == nil,
            parts.user == nil, parts.password == nil, parts.fragment == nil
        else { return nil }
        let path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
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
