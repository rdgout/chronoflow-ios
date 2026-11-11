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

        @Test func diagnosticRootsRequireColdLaunchButPlanRoutesCanReseed() {
            let environment = ["CF_UI_TEST_PROFILE": "screen", "CF_AUTH_TEST_ID": UUID().uuidString]
            let command = UITestSeedCommand(authorization: "", environment: environment, arguments: [])
            for arguments in [["-cf.trip-page", "S1"], ["-cf.session", "out"], ["-cf.timeline-fixtures"]] {
                #expect(command.changedLaunchSettings(arguments: arguments, environment: environment) == [arguments[0]])
                let diagnostic = UITestSeedCommand(authorization: "", environment: environment, arguments: arguments)
                #expect(diagnostic.changedLaunchSettings(arguments: [], environment: environment) == [arguments[0]])
                #expect(diagnostic.changedLaunchSettings(arguments: arguments, environment: environment).isEmpty)
            }
            var plan = environment
            plan["CF_PLAN_TEST_ROUTE"] = "trip:demo:list"
            plan["CF_PLAN_TEST_SHEET"] = "step:demo"
            plan["CF_PLAN_TEST_BLOCK"] = "demo"
            plan["CF_PLAN_TEST_POSITION"] = "summary"
            plan["CF_REFRESH_TEST_EMPTY_TRIPS"] = "1"
            plan["CF_REFRESH_TEST_COUNTER"] = "1"
            #expect(command.changedLaunchSettings(arguments: [], environment: plan).isEmpty)
        }

        @Test func rejectionReasonsSeparateDeliveryFromAuthorizationAndSeedValidation() throws {
            let id = UUID().uuidString
            let environment = ["CF_AUTH_TEST_ID": UUID().uuidString, "CF_UI_TEST_PROFILE": "screen"]
            let command = UITestSeedCommand(authorization: id, environment: environment, arguments: [])
            let url = try command.url()
            #expect(try UITestSeedCommand(validating: url, authorizedID: id.lowercased()) == command)
            #expect(throws: UITestSeedCommand.Rejection.missingAuthorization) {
                try UITestSeedCommand(validating: url, authorizedID: nil)
            }
            #expect(throws: UITestSeedCommand.Rejection.foreignAuthorization) {
                try UITestSeedCommand(validating: url, authorizedID: UUID().uuidString)
            }
            for (value, reason) in [
                ("https://reseed", UITestSeedCommand.Rejection.invalidEndpoint),
                ("chronoflow-uitest://reseed?payload=bad", .invalidPayload),
                ("chronoflow-uitest://reseed?payload=e30=", .malformedCommand),
            ] {
                let invalid = try #require(URL(string: value))
                #expect(throws: reason) { try UITestSeedCommand(validating: invalid, authorizedID: id) }
            }
            for (nonce, seed, reason) in [
                ("bad", environment, UITestSeedCommand.Rejection.invalidNonce),
                (UUID().uuidString, ["CF_UI_TEST_PROFILE": "screen"], .invalidTestID),
                (UUID().uuidString, ["CF_AUTH_TEST_ID": id, "CF_UI_TEST_PROFILE": "launch"], .invalidProfile),
                (
                    UUID().uuidString,
                    ["CF_AUTH_TEST_ID": id, "CF_UI_TEST_PROFILE": "screen", "AppleLocale": "nl"], .foreignEnvironment
                ),
            ] {
                let invalid = try UITestSeedCommand(authorization: id, nonce: nonce, environment: seed, arguments: [])
                    .url()
                #expect(throws: reason) { try UITestSeedCommand(validating: invalid, authorizedID: id) }
            }
        }

        @Test func launchSettingsIncludeRemovedTraitsDuplicateOverridesAndProcessEnvironment() {
            let environment = ["CF_UI_TEST_PROFILE": "screen", "CF_AUTH_TEST_ID": UUID().uuidString, "LANG": "en_US"]
            let arguments = [
                "-AppleLanguages", "(en)", "-UIKeyboardAutomaticMinimizationEnabled", "NO", "-cf.reduceMotion",
            ]
            let command = UITestSeedCommand(authorization: "", environment: environment, arguments: arguments)
            #expect(command.changedLaunchSettings(arguments: arguments, environment: environment).isEmpty)
            #expect(
                command.changedLaunchSettings(arguments: [], environment: environment) == [
                    "-AppleLanguages", "-UIKeyboardAutomaticMinimizationEnabled", "-cf.reduceMotion",
                ])
            #expect(
                command.changedLaunchSettings(
                    arguments: arguments + ["-AppleLanguages", "(nl)"], environment: environment) == ["-AppleLanguages"]
            )
            var changed = environment
            changed["LANG"] = "nl_NL"
            changed["CF_UI_TEST_PROFILE"] = "launch"
            #expect(
                command.changedLaunchSettings(arguments: arguments, environment: changed) == [
                    "CF_UI_TEST_PROFILE", "LANG",
                ])
            changed = environment
            changed["CF_AUTH_TEST_ID"] = UUID().uuidString
            changed["CF_AUTH_TEST_VERIFY_STATE"] = "throttle"
            changed["CF_UI_TEST_LAUNCH_ARGUMENTS"] = "[]"
            #expect(command.changedLaunchSettings(arguments: arguments, environment: changed).isEmpty)
        }
    }
#endif
