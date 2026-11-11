#if DEBUG
    import XCTest

    nonisolated final class WizardBoardCaptureTests: XCTestCase {
        override func setUp() {
            super.setUp()
            continueAfterFailure = false
            executionTimeAllowance = 3600
        }

        @MainActor func testEnglishBoardsInLightAndDark() throws { try capture(language: "en") }
        @MainActor func testDutchBoardsInLightAndDark() throws { try capture(language: "nl") }

        @MainActor private func capture(language: String) throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["TEST_RUNNER_WIZARD_BOARD_CAPTURE"] == "1")
            for theme in ["light", "dark"] {
                let app = XCUIApplication()
                defer { app.terminate() }
                app.launchArguments =
                    AuthUIFlow.arguments(language: language)
                    + ["-cf.settings.language", "system", "-cf.settings.theme", theme]
                app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
                app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
                for (index, board) in Self.boards.enumerated() {
                    app.launchEnvironment["CF_WIZARD_BOARD_CAPTURE"] = board
                    app.launch()
                    if index == 0 {
                        AuthUIFlow.openSignIn(app)
                        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
                    }
                    XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 15))
                    app.tabBars.buttons[language == "nl" ? "Mijn reizen" : "My trips"].tap()
                    let create = app.buttons["trips.create"]
                    XCTAssertTrue(create.waitForExistence(timeout: 10))
                    create.tap()
                    let screen = app.otherElements[Self.screen(board)]
                    XCTAssertTrue(screen.waitForExistence(timeout: 8), board)
                    let title = app.descendants(matching: .any)["wizard.title"]
                    let ready = XCTNSPredicateExpectation(
                        predicate: NSPredicate { _, _ in
                            title.exists && !title.label.isEmpty
                        }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
                    if [
                        "WizardAirportFrom", "WizardAirportHome", "WizardStopSearch", "WizardStopSearchSecond",
                        "WizardStopSearchHome",
                    ].contains(board) {
                        if board == "WizardStopSearch" || board == "WizardStopSearchHome" {
                            app.segmentedControls["wizard.route.stops"].buttons[language == "nl" ? "Ja" : "Yes"].tap()
                        } else {
                            app.buttons[
                                board == "WizardAirportFrom"
                                    ? "wizard.from" : board == "WizardAirportHome" ? "wizard.to" : "wizard.add-stop"
                            ].tap()
                        }
                        let search = app.descendants(matching: .any)["wizard.airport.query"].firstMatch
                        XCTAssertTrue(search.waitForExistence(timeout: 5))
                        search.tap()
                        let stop = board.hasPrefix("WizardStopSearch")
                        search.typeText(stop ? "Du" : "Am")
                        XCTAssertTrue(
                            app.buttons[stop ? "wizard.airport.DXB" : "wizard.airport.AMS"].waitForExistence(timeout: 8)
                        )
                    }
                    if board == "WizardDiscard" {
                        app.buttons["wizard.close"].tap()
                        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 4))
                    }
                    _ = try UIWait.stableFrames([app.windows.firstMatch], timeout: 5)
                    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    attachment.name = board + (theme == "dark" ? "Dark" : "") + (language == "nl" ? "NL" : "")
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    if app.alerts.firstMatch.exists {
                        app.alerts.buttons[language == "nl" ? "Verder bewerken" : "Keep editing"].tap()
                    }
                    if app.otherElements["wizard.airport-search"].exists {
                        app.buttons[language == "nl" ? "Annuleren" : "Cancel"].tap()
                    }
                    app.buttons["wizard.close"].tap()
                    if board != "WizardWhereEmpty" && board != "WizardAirportFrom" {
                        let discard = app.alerts.buttons[language == "nl" ? "Weggooien" : "Discard"]
                        XCTAssertTrue(discard.waitForExistence(timeout: 4))
                        discard.tap()
                    }
                    XCTAssertTrue(app.buttons["trips.create"].waitForExistence(timeout: 5))
                    app.terminate()
                }
            }
        }

        private static func screen(_ board: String) -> String {
            if board.hasPrefix("WizardWhere") || board == "WizardAirportFrom" || board == "WizardStopSearch"
                || board == "WizardStopSearchSecond"
            {
                return "wizard.where"
            }
            if board.hasPrefix("WizardHomeRoute") || board == "WizardAirportHome" || board == "WizardStopSearchHome" {
                return "wizard.return-route"
            }
            if board == "WizardReturn" || board == "WizardReturnWeb" { return "wizard.return" }
            if board.hasPrefix("WizardReturnFlight") { return "wizard.return-flight" }
            if board == "WizardSleep" { return "wizard.sleep" }
            if board.hasPrefix("WizardCheck") { return "wizard.checking" }
            if board.hasPrefix("WizardQ") { return "wizard.question.0" }
            if board.hasPrefix("WizardExcluded") { return "wizard.excluded" }
            return "wizard.outbound"
        }

        private static var boards: [String] {
            [
                "WizardWhereEmpty", "WizardWhere", "WizardWhereSame", "WizardAirportFrom", "WizardAirportHome",
                "WizardStopSearch", "WizardStopSearchSecond", "WizardStopSearchHome",
                "WizardWhereStop", "WizardWhereStops", "WizardHomeRoute", "WizardHomeRouteStop",
                "WizardOutboundThree", "WizardOutboundTwoErrors", "WizardOutboundStopEmpty",
                "WizardOutboundEmpty", "WizardOutbound", "WizardOutboundErrors", "WizardOutboundPast",
                "WizardOutboundStopNew", "WizardOutboundStop", "WizardOutboundOvernight",
                "WizardReturn", "WizardReturnWeb", "WizardReturnFlight", "WizardReturnFlightPast", "WizardSleep",
                "WizardChecking", "WizardCheckingAgain", "WizardCheckingSlow", "WizardCheckOffline",
                "WizardCheckServer", "WizardCheckThrottle",
                "WizardQAge", "WizardQBipolar", "WizardQPregnant", "WizardQShift", "WizardQCaffeine", "WizardQEye",
                "WizardQClot",
                "WizardExcluded", "WizardExcludedShift", "WizardDiscard",
            ]
        }
    }
#endif
