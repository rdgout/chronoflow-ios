#if DEBUG
    import XCTest

    nonisolated class WizardBoardCaptureTests: ScreenTestCase {
        var captureLanguage: String { "en" }
        var captureTheme: String { "light" }

        override func setUp() async throws {
            try await super.setUp()
            executionTimeAllowance = 60
        }

        @MainActor func testWhereEmpty() throws { try capture("WizardWhereEmpty") }
        @MainActor func testWhere() throws { try capture("WizardWhere") }
        @MainActor func testWhereSame() throws { try capture("WizardWhereSame") }
        @MainActor func testAirportFrom() throws { try capture("WizardAirportFrom") }
        @MainActor func testAirportHome() throws { try capture("WizardAirportHome") }
        @MainActor func testStopSearch() throws { try capture("WizardStopSearch") }
        @MainActor func testStopSearchSecond() throws { try capture("WizardStopSearchSecond") }
        @MainActor func testStopSearchHome() throws { try capture("WizardStopSearchHome") }
        @MainActor func testWhereStop() throws { try capture("WizardWhereStop") }
        @MainActor func testWhereStops() throws { try capture("WizardWhereStops") }
        @MainActor func testHomeRoute() throws { try capture("WizardHomeRoute") }
        @MainActor func testHomeRouteStop() throws { try capture("WizardHomeRouteStop") }
        @MainActor func testOutboundThree() throws { try capture("WizardOutboundThree") }
        @MainActor func testOutboundTwoErrors() throws { try capture("WizardOutboundTwoErrors") }
        @MainActor func testOutboundStopEmpty() throws { try capture("WizardOutboundStopEmpty") }
        @MainActor func testOutboundEmpty() throws { try capture("WizardOutboundEmpty") }
        @MainActor func testOutbound() throws { try capture("WizardOutbound") }
        @MainActor func testOutboundErrors() throws { try capture("WizardOutboundErrors") }
        @MainActor func testOutboundPast() throws { try capture("WizardOutboundPast") }
        @MainActor func testOutboundStopNew() throws { try capture("WizardOutboundStopNew") }
        @MainActor func testOutboundStop() throws { try capture("WizardOutboundStop") }
        @MainActor func testOutboundOvernight() throws { try capture("WizardOutboundOvernight") }
        @MainActor func testReturn() throws { try capture("WizardReturn") }
        @MainActor func testReturnWeb() throws { try capture("WizardReturnWeb") }
        @MainActor func testReturnFlight() throws { try capture("WizardReturnFlight") }
        @MainActor func testReturnFlightPast() throws { try capture("WizardReturnFlightPast") }
        @MainActor func testSleep() throws { try capture("WizardSleep") }
        @MainActor func testChecking() throws { try capture("WizardChecking") }
        @MainActor func testCheckingAgain() throws { try capture("WizardCheckingAgain") }
        @MainActor func testCheckingSlow() throws { try capture("WizardCheckingSlow") }
        @MainActor func testCheckOffline() throws { try capture("WizardCheckOffline") }
        @MainActor func testCheckServer() throws { try capture("WizardCheckServer") }
        @MainActor func testCheckThrottle() throws { try capture("WizardCheckThrottle") }
        @MainActor func testQAge() throws { try capture("WizardQAge") }
        @MainActor func testQBipolar() throws { try capture("WizardQBipolar") }
        @MainActor func testQPregnant() throws { try capture("WizardQPregnant") }
        @MainActor func testQShift() throws { try capture("WizardQShift") }
        @MainActor func testQCaffeine() throws { try capture("WizardQCaffeine") }
        @MainActor func testQEye() throws { try capture("WizardQEye") }
        @MainActor func testQClot() throws { try capture("WizardQClot") }
        @MainActor func testExcluded() throws { try capture("WizardExcluded") }
        @MainActor func testExcludedShift() throws { try capture("WizardExcludedShift") }
        @MainActor func testDiscard() throws { try capture("WizardDiscard") }
        @MainActor func testFineTune() throws { try capture("WizardFineTune") }
        @MainActor func testFineTuneBusy() throws { try capture("WizardFineTuneBusy") }
        @MainActor func testFineTuneMulti() throws { try capture("WizardFineTuneMulti") }
        @MainActor func testFineTuneNone() throws { try capture("WizardFineTuneNone") }
        @MainActor func testFineTuneSleep() throws { try capture("WizardFineTuneSleep") }
        @MainActor func testFineTuneSheet() throws { try capture("WizardFineTuneSheet") }
        @MainActor func testSheet() throws { try capture("WizardSheet") }
        @MainActor func testSheetBlue() throws { try capture("WizardSheetBlue") }
        @MainActor func testSheetBlueError() throws { try capture("WizardSheetBlueError") }
        @MainActor func testSheetBusy() throws { try capture("WizardSheetBusy") }
        @MainActor func testSheetCheckout() throws { try capture("WizardSheetCheckout") }
        @MainActor func testSheetDrinks() throws { try capture("WizardSheetDrinks") }
        @MainActor func testSheetDrinksError() throws { try capture("WizardSheetDrinksError") }
        @MainActor func testSheetFreeSleep() throws { try capture("WizardSheetFreeSleep") }
        @MainActor func testSheetLight() throws { try capture("WizardSheetLight") }
        @MainActor func testSheetRoom() throws { try capture("WizardSheetRoom") }
        @MainActor func testSheetWake() throws { try capture("WizardSheetWake") }
        @MainActor func testReady() throws { try capture("WizardReady") }
        @MainActor func testReadyReturn() throws { try capture("WizardReadyReturn") }
        @MainActor func testReadyUnlimited() throws { try capture("WizardReadyUnlimited") }
        @MainActor func testReadyFree() throws { try capture("WizardReadyFree") }
        @MainActor func testReadyOneFree() throws { try capture("WizardReadyOneFree") }
        @MainActor func testReadyAdjusted() throws { try capture("WizardReadyAdjusted") }
        @MainActor func testReadyNoCredits() throws { try capture("WizardReadyNoCredits") }
        @MainActor func testReadyChecking() throws { try capture("WizardReadyChecking") }
        @MainActor func testCalculating() throws { try capture("WizardCalculating") }
        @MainActor func testSaveOffline() throws { try capture("WizardSaveOffline") }
        @MainActor func testSaveServer() throws { try capture("WizardSaveServer") }

        @MainActor private func capture(_ board: String) throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["TEST_RUNNER_WIZARD_BOARD_CAPTURE"] == "1")
            let language = captureLanguage
            let app = ScreenTestApp.makeApplication()
            app.launchArguments =
                AuthUIFlow.arguments(language: language)
                + ["-cf.settings.language", "system", "-cf.settings.theme", captureTheme]
            AuthUIFlow.launchSignedIn(
                app, walkthroughSeen: true,
                extraEnv: ["CF_WIZARD_BOARD_CAPTURE": board, "CF_WIZARD_AUTO_OPEN": "1"])
            XCTAssertTrue(app.otherElements[Self.screen(board)].waitUntil(.exists, timeout: 5), board)
            let title = app.staticTexts["wizard.title"].firstMatch
            XCTAssertTrue(UIWait.until(timeout: 3) { title.exists && !title.label.isEmpty })
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
                let search = app.searchFields["wizard.airport.query"].firstMatch
                XCTAssertTrue(search.waitUntil(.hittable, timeout: 3))
                search.tap()
                let stop = board.hasPrefix("WizardStopSearch")
                search.typeText(stop ? "Du" : "Am")
                XCTAssertTrue(
                    app.buttons[stop ? "wizard.airport.DXB" : "wizard.airport.AMS"].waitUntil(.exists, timeout: 3))
            }
            if board == "WizardDiscard" {
                app.buttons["wizard.close"].tap()
                XCTAssertTrue(app.alerts.firstMatch.waitUntil(.exists, timeout: 3))
            }
            _ = try UIWait.stableFrames([app.windows.firstMatch], timeout: 3)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = board + (captureTheme == "dark" ? "Dark" : "") + (language == "nl" ? "NL" : "")
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        private static func screen(_ board: String) -> String {
            if board.hasPrefix("WizardFineTune") || board.hasPrefix("WizardSheet") { return "wizard.fine-tune" }
            if board.hasPrefix("WizardReady") || board.hasPrefix("WizardSave") { return "wizard.ready" }
            if board == "WizardCalculating" { return "wizard.calculating" }
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

    }

    nonisolated final class WizardBoardCaptureDarkTests: WizardBoardCaptureTests {
        override var captureTheme: String { "dark" }
    }

    nonisolated final class WizardBoardCaptureDutchTests: WizardBoardCaptureTests {
        override var captureLanguage: String { "nl" }
    }

    nonisolated final class WizardBoardCaptureDutchDarkTests: WizardBoardCaptureTests {
        override var captureLanguage: String { "nl" }
        override var captureTheme: String { "dark" }
    }
#endif
