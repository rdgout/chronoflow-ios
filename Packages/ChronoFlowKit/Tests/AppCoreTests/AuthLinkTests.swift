import AppCore
import Foundation
import Testing

struct AuthLinkTests {
    @Test func exactResetURLDecodesOnceAndKeepsPlusPercentAndUnicode() throws {
        let encoded = try #require(
            URL(string: "https://app.chronoflow.net/reset-password/a%2Fb%252F?email=rick%2B100%25%40example.com"))
        let value = try #require(AuthLink(url: encoded))
        #expect(value == .reset(ResetPasswordLink(token: "a/b%2F", email: "rick+100%@example.com")))
        for path in [
            "/reset-password", "/reset-password/", "/reset-password/token", "/reset-password/token?email=a&email=b",
            "/reset-password/a/b?email=a",
        ] {
            guard case .reset(let input) = AuthLink(url: try #require(URL(string: "https://app.chronoflow.net" + path)))
            else {
                Issue.record("Unrecognized path \(path)")
                continue
            }
            #expect(!input.isValid)
        }
        for url in [
            "http://app.chronoflow.net/reset-password/a?email=b", "https://evil.test/reset-password/a?email=b",
            "https://app.chronoflow.net:443/reset-password/a?email=b",
            "https://user@app.chronoflow.net/reset-password/a?email=b",
            "https://app.chronoflow.net/reset-password/a?email=b#c", "chronoflow://reset/a",
            "https://app.chronoflow.net/other",
        ] {
            let input = try #require(URL(string: url))
            #expect(AuthLink(url: input) == nil)
        }
    }
}
