#if DEBUG
    import XCTest

    nonisolated final class SettingsBoardCaptureTests: XCTestCase {
        override func setUp() {
            super.setUp()
            continueAfterFailure = false
            executionTimeAllowance = 1200
        }
        @MainActor func testEnglishLightPages() throws { try boards(language: "en", appearance: .light, states: false) }
        @MainActor func testEnglishLightStates() throws { try boards(language: "en", appearance: .light, states: true) }
        @MainActor func testEnglishDarkPages() throws { try boards(language: "en", appearance: .dark, states: false) }
        @MainActor func testEnglishDarkStates() throws { try boards(language: "en", appearance: .dark, states: true) }
        @MainActor func testDutchLightPages() throws { try boards(language: "nl", appearance: .light, states: false) }
        @MainActor func testDutchLightStates() throws { try boards(language: "nl", appearance: .light, states: true) }
        @MainActor func testDutchDarkPages() throws { try boards(language: "nl", appearance: .dark, states: false) }
        @MainActor func testDutchDarkStates() throws { try boards(language: "nl", appearance: .dark, states: true) }

        @MainActor private func boards(language: String, appearance: XCUIDevice.Appearance, states: Bool) throws {
            let previous = XCUIDevice.shared.appearance
            XCUIDevice.shared.appearance = appearance
            defer { XCUIDevice.shared.appearance = previous }
            let suffix = language + (appearance == .dark ? "-dark" : "-light")
            guard states else { return try corePages(language: language, suffix: suffix) }
            for (state, board) in [
                ("planCredits", "SetPlanCredits"), ("planUnlimited", "SetPlan"),
                ("planOffline", "SetPlanOffline"), ("planLoading", "SetPlanLoading"),
                ("accountMissing", "SetStatesMore-AccountNotLoaded"),
                ("bodyMissing", "SetBodyClock-NeedsAnswers"), ("bodyExcluded", "SetBodyClock-Excluded"),
                ("promptLocked", "PasswordPromptLocked"), ("promptChecking", "PasswordPromptChecking"),
            ] {
                let app = launch(language: language, state: state)
                defer { app.terminate() }
                if state.hasPrefix("plan") {
                    open("settings.plan", app: app)
                } else if state == "accountMissing" {
                    open("settings.account", app: app)
                } else if state.hasPrefix("body") {
                    open("settings.bodyClock", app: app)
                } else if state == "promptLocked" {
                    open("settings.account", app: app)
                    open("settings.account.delete", app: app)
                    open("settings.delete.confirm", app: app)
                    fill("settings.delete.password", "password", app: app)
                    open("settings.delete.submit", app: app)
                    wait("settings.delete.error", app: app)
                } else {
                    open("settings.security", app: app)
                    open("settings.security.twoFactor", app: app)
                    open("settings.twoFactor.enable", app: app)
                    fill("settings.security.prompt.password", "password", app: app)
                    open("settings.security.prompt.submit", app: app)
                    let checking = app.buttons["settings.security.prompt.submit"]
                    let ready = XCTNSPredicateExpectation(
                        predicate: NSPredicate { _, _ in
                            checking.exists && !checking.isEnabled
                                && checking.label.contains(language == "nl" ? "Controleren" : "Checking")
                        }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
                }
                if state == "planOffline" { wait("settings.plan.balance", app: app) }
                if state == "planLoading" { wait("settings.plan.loading", app: app) }
                try capture(board, suffix: suffix, app: app)
                if state == "bodyMissing" {
                    AuthUIFlow.reveal(app.buttons["settings.bodyClock.caffeineRuledOut.no"], in: app)
                    try capture("SetBodyClock-NeedsAnAnswer", suffix: suffix, app: app)
                }
            }
            for permission in ["undetermined", "blocked", "unsupported"] {
                let app = launch(language: language, permission: permission)
                defer { app.terminate() }
                open("settings.preferences", app: app)
                open("settings.preferences.reminders", app: app)
                let board =
                    permission == "undetermined"
                    ? "SetRemindersAsk" : permission == "blocked" ? "SetRemindersBlocked" : "SetReminders-Unsupported"
                wait(
                    permission == "undetermined"
                        ? "reminders.ask" : permission == "blocked" ? "reminders.blocked" : "reminders.unsupported",
                    app: app
                )
                try capture(board, suffix: suffix, app: app)
            }
        }
        @MainActor private func corePages(language: String, suffix: String) throws {
            let app = launch(language: language)
            defer { app.terminate() }
            try capture("SetHome", suffix: suffix, app: app)
            open("settings.account", app: app)
            try capture("SetAccount", suffix: suffix, app: app)
            open("settings.account.profile", app: app)
            try capture("SetProfile", suffix: suffix, app: app)
            let name = app.textFields["settings.profile.name"]
            AuthUIFlow.reveal(name, in: app)
            name.tap()
            name.typeText(" Board")
            open("settings.profile.save", app: app)
            wait("settings.profile.saved", app: app)
            try capture("SetStates-ProfileSaved", suffix: suffix, app: app)
            back(app)
            open("settings.account.language", app: app)
            try capture("SetLanguage", suffix: suffix, app: app)
            open("settings.language.choice." + language, app: app)
            wait("settings.language.saved", app: app)
            try capture("SetLanguage-Saved", suffix: suffix, app: app)
            back(app)
            open("settings.account.delete", app: app)
            wait("settings.delete.confirm", app: app)
            try capture("SetDelete", suffix: suffix, app: app)
            open("settings.delete.confirm", app: app)
            wait("settings.delete.password", app: app)
            try capture("PasswordPromptDelete", suffix: suffix, app: app)
            cancel(language, app: app)
            back(app)
            open("settings.bodyClock", app: app)
            try capture("SetBodyClock", suffix: suffix, app: app)
            for (option, part) in [
                ("freeDayStatus.declared", "Sleep"), ("caffeineHabit.cups", "Caffeine"),
                ("blueBlockers.rated", "Light"), ("shiftWork.no", "Health"),
            ] {
                let target = app.buttons["settings.bodyClock." + option]
                AuthUIFlow.reveal(target, in: app)
                try capture("SetBodyClock-" + part, suffix: suffix, app: app)
            }
            back(app)
            open("settings.preferences", app: app)
            try capture("SetPreferences", suffix: suffix, app: app)
            AuthUIFlow.reveal(app.buttons["settings.preferences.reminders"], in: app)
            try capture("SetPreferences-Links", suffix: suffix, app: app)
            open("settings.preferences.reminders", app: app)
            wait("reminders.enabled", app: app)
            try capture("SetReminders", suffix: suffix, app: app)
            back(app)
            back(app)
            open("settings.plan", app: app)
            wait("settings.plan.balance", app: app)
            try capture("SetPlanNoLink", suffix: suffix, app: app)
            back(app)
            open("settings.security", app: app)
            try capture("SetSecurity", suffix: suffix, app: app)
            open("settings.security.password", app: app)
            fill("settings.password.current", "password", app: app)
            fill("settings.password.new", "New password1!", app: app)
            fill("settings.password.confirmation", "Different1!", app: app)
            open("settings.password.save", app: app)
            try capture("SetPassword", suffix: suffix, app: app)
            back(app)
            open("settings.security.twoFactor", app: app)
            try capture("Set2FA", suffix: suffix, app: app)
            open("settings.twoFactor.enable", app: app)
            wait("settings.security.prompt.password", app: app)
            try capture("PasswordPrompt2FAOn", suffix: suffix, app: app)
            open("settings.security.prompt.forgot", app: app)
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 8))
            try capture("PasswordPromptForgot", suffix: suffix, app: app)
            app.alerts.buttons[language == "nl" ? "Annuleren" : "Cancel"].tap()
            fill("settings.security.prompt.password", "wrong", app: app)
            open("settings.security.prompt.submit", app: app)
            wait("settings.security.prompt.error", app: app)
            try capture("PasswordPrompt2FAOn-Wrong", suffix: suffix, app: app)
            fill("settings.security.prompt.password", "password", app: app)
            open("settings.security.prompt.submit", app: app)
            XCTAssertTrue(app.buttons["settings.security.prompt.submit"].waitForNonExistence(timeout: 8))
            wait("settings.twoFactor.code", app: app)
            try capture("Set2FASetup", suffix: suffix, app: app)
            let code = app.textFields["settings.twoFactor.code"]
            AuthUIFlow.reveal(code, in: app)
            code.tap()
            code.typeText("123456")
            open("settings.twoFactor.confirm", app: app)
            wait("settings.twoFactor.recoveryCode", app: app)
            let since = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", language == "nl" ? "Sinds " : "Since ")
            ).firstMatch
            XCTAssertTrue(since.waitForExistence(timeout: 8))
            try capture("Set2FAOn", suffix: suffix, app: app)
            back(app)
            open("settings.security.twoFactor", app: app)
            wait("settings.twoFactor.reveal", app: app)
            try capture("Set2FAManage", suffix: suffix, app: app)
            open("settings.twoFactor.regenerate", app: app)
            try capture("PasswordPromptNewCodes", suffix: suffix, app: app)
            fill("settings.security.prompt.password", "wrong", app: app)
            open("settings.security.prompt.submit", app: app)
            wait("settings.security.prompt.error", app: app)
            try capture(
                language == "nl" ? "PasswordPromptNL" : "PasswordPromptNewCodes-Wrong", suffix: suffix, app: app)
            cancel(language, app: app)
            open("settings.twoFactor.disable", app: app)
            try capture("PasswordPrompt-TurnOff", suffix: suffix, app: app)
            fill("settings.security.prompt.password", "wrong", app: app)
            open("settings.security.prompt.submit", app: app)
            wait("settings.security.prompt.error", app: app)
            try capture("PasswordPromptWrong", suffix: suffix, app: app)
            cancel(language, app: app)
            open("settings.twoFactor.reveal", app: app)
            try capture("PasswordPrompt", suffix: suffix, app: app)
            try capture("PasswordPrompt-ShowCodes", suffix: suffix, app: app)
            fill("settings.security.prompt.password", "password", app: app)
            open("settings.security.prompt.submit", app: app)
            wait("settings.twoFactor.recoveryCode", app: app)
            try capture("Set2FACodes", suffix: suffix, app: app)
        }
        @MainActor private func launch(language: String, state: String? = nil, permission: String = "granted")
            -> XCUIApplication
        {
            let app = XCUIApplication()
            app.launchArguments =
                AuthUIFlow.arguments(language: language) + [
                    "-cf.notificationAuthorization", permission, "-cf.settings.theme", "system",
                    "-cf.settings.language", "system",
                ]
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
            if let state { app.launchEnvironment["CF_SETTINGS_BOARD_STATE"] = state }
            app.launch()
            AuthUIFlow.openSignIn(app)
            AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
            let settings = app.tabBars.buttons[language == "nl" ? "Instellingen" : "Settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 12))
            settings.tap()
            wait("settings.account", app: app)
            return app
        }
        @MainActor private func capture(_ board: String, suffix: String, app: XCUIApplication) throws {
            _ = try? UIWait.stableFrames([app.windows.firstMatch], timeout: 3)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            let dutchNames = [
                "SetHome": "SetHomeNL", "SetPreferences": "SetPreferencesNL", "Set2FA": "Set2FANL",
                "Set2FAManage": "Set2FAManageNL",
            ]
            let name = suffix.hasPrefix("nl") ? dutchNames[board] ?? board : board
            attachment.name = name + "-" + suffix
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        @MainActor private func open(_ identifier: String, app: XCUIApplication) {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 8))
            AuthUIFlow.reveal(button, in: app)
            AuthUIFlow.waitUntilEnabled(button)
            button.tap()
        }
        @MainActor private func wait(_ identifier: String, app: XCUIApplication) {
            XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: 8))
        }
        @MainActor private func fill(_ identifier: String, _ value: String, app: XCUIApplication) {
            let field = app.secureTextFields[identifier]
            XCTAssertTrue(field.waitForExistence(timeout: 8))
            AuthUIFlow.reveal(field, in: app)
            XCTAssertTrue(
                AuthUIFlow.type(
                    value, into: field, in: app,
                    newPassword: identifier == "settings.password.new" || identifier == "settings.password.confirmation"
                ))
        }
        @MainActor private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }
        @MainActor private func cancel(_ language: String, app: XCUIApplication) {
            app.navigationBars.buttons[language == "nl" ? "Annuleren" : "Cancel"].tap()
        }
    }
#endif
