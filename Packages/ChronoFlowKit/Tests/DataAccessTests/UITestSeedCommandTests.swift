#if DEBUG
    import DataAccess
    import Foundation
    import Testing

    struct UITestSeedCommandTests {
        @Test func roundTripsEverySeedAndRejectsForeignOrMalformedCommands() throws {
            let id = UUID().uuidString
            let command = UITestSeedCommand(
                authorization: id,
                environment: [
                    "CF_AUTH_TEST_ID": UUID().uuidString, "CF_UI_TEST_PROFILE": "screen",
                    "CF_SETTINGS_ROUTE": "profile",
                ],
                arguments: ["-cf.reduceMotion", "-AppleLanguages", "(en)"])
            let url = try command.url()
            #expect(UITestSeedCommand(url: url, authorizedID: id) == command)
            #expect(UITestSeedCommand(url: url, authorizedID: UUID().uuidString) == nil)
            for value in [
                "chronoflow-uitest://reseed", "https://reseed?payload=bad", "chronoflow-uitest://reseed?payload=bad",
            ] {
                #expect(UITestSeedCommand(url: try #require(URL(string: value)), authorizedID: id) == nil)
            }
            for environment in [
                ["CF_UI_TEST_PROFILE": "screen"], ["CF_AUTH_TEST_ID": id, "CF_UI_TEST_PROFILE": "launch"],
                ["CF_AUTH_TEST_ID": id, "CF_UI_TEST_PROFILE": "screen", "AppleLanguages": "nl"],
            ] {
                let rejected = UITestSeedCommand(authorization: id, environment: environment, arguments: [])
                #expect(UITestSeedCommand(url: try rejected.url(), authorizedID: id) == nil)
            }
        }

        @Test func processOnlyTraitsCannotChangeDuringReseed() {
            let args = [
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Light",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            ]
            let command = UITestSeedCommand(authorization: UUID().uuidString, environment: [:], arguments: args)
            #expect(command.preservesLaunchSettings(in: ["/app/executable"] + args + ["-extra-system-argument"]))
            for index in stride(from: 1, to: args.count, by: 2) {
                var changed = args
                changed[index] = "different"
                #expect(!command.preservesLaunchSettings(in: changed))
            }
        }
    }
#endif
