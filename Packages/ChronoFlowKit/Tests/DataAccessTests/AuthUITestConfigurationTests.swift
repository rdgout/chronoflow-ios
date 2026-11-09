#if DEBUG
    import DataAccess
    import Foundation
    import Testing

    struct AuthUITestConfigurationTests {
        @Test func isolatedFixtureRequiresUUIDAndKnownSignedInAccount() throws {
            for environment in [[:], ["CF_AUTH_TEST_ID": "invalid"], ["CF_AUTH_TEST_SIGNED_IN": "demo"]] {
                #expect(AuthUITestConfiguration(environment: environment) == nil)
            }
            let id = UUID().uuidString
            for account in ["demo", "twofactor", "unknown"] {
                let configuration = try #require(
                    AuthUITestConfiguration(environment: [
                        "CF_AUTH_TEST_ID": id, "CF_AUTH_TEST_SIGNED_IN": account,
                    ]))
                #expect(configuration.id == id.lowercased())
                #expect(configuration.signedInAccount == (account == "unknown" ? nil : account))
                #expect(!configuration.walkthroughSeen && !configuration.offline && !configuration.unverified)
                #expect(
                    !configuration.settingsPending && !configuration.walkthroughPending && !configuration.termsPending)
                #expect(
                    configuration.applicationSupport(in: URL(filePath: "/fixture")).path
                        == "/fixture/AuthUITests/" + id.lowercased())
            }
        }

        @Test(arguments: ["0", "1", "true"])
        func flagsRequireExplicitOne(value: String) throws {
            let configuration = try #require(
                AuthUITestConfiguration(environment: [
                    "CF_AUTH_TEST_ID": UUID().uuidString, "CF_AUTH_TEST_OFFLINE": value,
                    "CF_SETTINGS_TEST_PENDING": value, "CF_WALKTHROUGH_TEST_PENDING": value,
                    "CF_AUTH_TEST_TERMS_PENDING": value, "CF_AUTH_TEST_UNVERIFIED": value,
                    "CF_AUTH_TEST_WALKTHROUGH_SEEN": value,
                    "CF_AUTH_TEST_AUDIT_SCREEN": "reset", "CF_AUTH_TEST_AUDIT_STATE": "server",
                ]))
            for flag in [
                configuration.offline, configuration.settingsPending, configuration.walkthroughPending,
                configuration.termsPending, configuration.unverified, configuration.walkthroughSeen,
            ] {
                #expect(flag == (value == "1"))
            }
            #expect(configuration.auditScreen == "reset" && configuration.auditState == "server")
        }
    }
#endif
