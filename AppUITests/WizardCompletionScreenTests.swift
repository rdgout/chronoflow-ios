import XCTest

nonisolated final class WizardCompletionScreenTests: ScreenTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 300
    }

    @MainActor func testFineTuneBoardsKeepControlsAndFooter() {
        for board in [
            "WizardFineTune", "WizardFineTuneMulti", "WizardFineTuneNone", "WizardFineTuneSleep", "WizardFineTuneBusy",
        ] {
            let app = WizardScreenUIFlow.launchCompletion(board)
            XCTAssertTrue(app.otherElements["wizard.fine-tune"].waitForExistence(timeout: 5))
            let next = app.buttons["wizard.fine-tune.continue"]
            XCTAssertTrue(next.isHittable)
            XCTAssertEqual(next.isEnabled, board != "WizardFineTuneBusy")
            if board == "WizardFineTuneNone" {
                XCTAssertFalse(
                    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'wizard.extra.'")).firstMatch.exists
                )
            }
        }
    }

    @MainActor func testReadyPricesErrorsAndCheckingStayOnReady() {
        for board in [
            "WizardReady", "WizardReadyReturn", "WizardReadyUnlimited", "WizardReadyFree", "WizardReadyOneFree",
            "WizardReadyAdjusted", "WizardReadyChecking", "WizardSaveOffline", "WizardSaveServer",
        ] {
            let app = WizardScreenUIFlow.launchCompletion(board)
            XCTAssertTrue(app.otherElements["wizard.ready"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["wizard.ready.continue"].isHittable)
            XCTAssertEqual(app.buttons["wizard.ready.continue"].isEnabled, board != "WizardReadyChecking")
            if board == "WizardSaveOffline" {
                XCTAssertTrue(app.descendants(matching: .any)["wizard.save.offline"].waitForExistence(timeout: 5))
            }
            if board == "WizardSaveServer" {
                XCTAssertTrue(app.descendants(matching: .any)["wizard.save.server"].waitForExistence(timeout: 5))
            }
        }
    }

    @MainActor func testNoCreditsOffersCloseWithoutBillingOrSaveAction() {
        let app = WizardScreenUIFlow.launchCompletion("WizardReadyNoCredits", language: "nl")
        XCTAssertTrue(app.otherElements["wizard.ready"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["wizard.ready.continue"].exists)
        let close = app.buttons["wizard.ready.no-credits"]
        AuthUIFlow.reveal(close, in: app, scroll: app.scrollViews.firstMatch)
        XCTAssertTrue(close.isHittable)
    }

    @MainActor func testAllAnswerSheetsUseNativeDoneAndCancel() {
        for board in [
            "WizardSheet", "WizardSheetBlue", "WizardSheetBlueError", "WizardSheetBusy", "WizardSheetCheckout",
            "WizardSheetDrinks", "WizardSheetDrinksError", "WizardSheetFreeSleep", "WizardSheetLight",
            "WizardSheetRoom", "WizardSheetWake",
        ] {
            let app = WizardScreenUIFlow.launchCompletion(board, language: "nl")
            XCTAssertTrue(app.buttons["wizard.answer.cancel"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["wizard.answer.done"].exists)
            if board.hasSuffix("Error") {
                XCTAssertFalse(app.buttons["wizard.answer.done"].isEnabled)
                XCTAssertTrue(app.descendants(matching: .any)["wizard.answer.error"].exists)
            }
        }
    }

    @MainActor func testCalculatingHasNoExitAndSwipeDoesNothing() {
        let app = WizardScreenUIFlow.launchCompletion("WizardCalculating")
        XCTAssertTrue(app.otherElements["wizard.calculating"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["wizard.close"].exists)
        XCTAssertFalse(app.navigationBars.buttons.firstMatch.exists)
        app.swipeRight()
        XCTAssertTrue(app.otherElements["wizard.calculating"].exists)
    }
}
