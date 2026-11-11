import XCTest

nonisolated final class WizardCompletionScreenTests: ScreenTestCase {
    override func setUp() async throws {
        try await super.setUp()
        executionTimeAllowance = 60
    }

    @MainActor func testFineTune() { assertFineTune("WizardFineTune") }
    @MainActor func testFineTuneMulti() { assertFineTune("WizardFineTuneMulti") }
    @MainActor func testFineTuneNone() { assertFineTune("WizardFineTuneNone") }
    @MainActor func testFineTuneSleep() { assertFineTune("WizardFineTuneSleep") }
    @MainActor func testFineTuneBusy() { assertFineTune("WizardFineTuneBusy") }

    @MainActor func testReady() { assertReady("WizardReady") }
    @MainActor func testReadyReturn() { assertReady("WizardReadyReturn") }
    @MainActor func testReadyUnlimited() { assertReady("WizardReadyUnlimited") }
    @MainActor func testReadyFree() { assertReady("WizardReadyFree") }
    @MainActor func testReadyOneFree() { assertReady("WizardReadyOneFree") }
    @MainActor func testReadyAdjusted() { assertReady("WizardReadyAdjusted") }
    @MainActor func testReadyChecking() { assertReady("WizardReadyChecking") }
    @MainActor func testSaveOffline() { assertReady("WizardSaveOffline") }
    @MainActor func testSaveServer() { assertReady("WizardSaveServer") }

    @MainActor func testNoCreditsOffersCloseWithoutBillingOrSaveAction() {
        let app = WizardScreenUIFlow.launchCompletion("WizardReadyNoCredits", language: "nl")
        XCTAssertTrue(app.otherElements["wizard.ready"].waitUntil(.exists, timeout: 3))
        XCTAssertFalse(app.buttons["wizard.ready.continue"].exists)
        let close = app.buttons["wizard.ready.no-credits"]
        XCTAssertTrue(close.waitUntil(.hittable, timeout: 3))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(close.frame))
    }

    @MainActor func testSheet() { assertAnswerSheet("WizardSheet") }
    @MainActor func testSheetBlue() { assertAnswerSheet("WizardSheetBlue") }
    @MainActor func testSheetBlueError() { assertAnswerSheet("WizardSheetBlueError") }
    @MainActor func testSheetBusy() { assertAnswerSheet("WizardSheetBusy") }
    @MainActor func testSheetCheckout() { assertAnswerSheet("WizardSheetCheckout") }
    @MainActor func testSheetDrinks() { assertAnswerSheet("WizardSheetDrinks") }
    @MainActor func testSheetDrinksError() { assertAnswerSheet("WizardSheetDrinksError") }
    @MainActor func testSheetFreeSleep() { assertAnswerSheet("WizardSheetFreeSleep") }
    @MainActor func testSheetLight() { assertAnswerSheet("WizardSheetLight") }
    @MainActor func testSheetRoom() { assertAnswerSheet("WizardSheetRoom") }
    @MainActor func testSheetWake() { assertAnswerSheet("WizardSheetWake") }

    @MainActor func testCalculatingHasNoExitAndSwipeDoesNothing() {
        let app = WizardScreenUIFlow.launchCompletion("WizardCalculating", language: "nl")
        XCTAssertTrue(app.otherElements["wizard.calculating"].waitUntil(.exists, timeout: 3))
        XCTAssertFalse(app.buttons["wizard.close"].exists)
        XCTAssertFalse(app.navigationBars.buttons.firstMatch.exists)
        app.swipeRight()
        XCTAssertTrue(app.otherElements["wizard.calculating"].exists)
    }

    @MainActor private func assertFineTune(_ board: String) {
        let app = WizardScreenUIFlow.launchCompletion(board, language: "nl")
        XCTAssertTrue(app.otherElements["wizard.fine-tune"].waitUntil(.exists, timeout: 3))
        let next = app.buttons["wizard.fine-tune.continue"]
        XCTAssertTrue(next.isHittable)
        XCTAssertEqual(next.isEnabled, board != "WizardFineTuneBusy")
        if board == "WizardFineTuneNone" {
            XCTAssertFalse(app.otherElements["wizard.extras"].exists)
        }
    }

    @MainActor private func assertReady(_ board: String) {
        let app = WizardScreenUIFlow.launchCompletion(board, language: "nl")
        XCTAssertTrue(app.otherElements["wizard.ready"].waitUntil(.exists, timeout: 3))
        XCTAssertTrue(app.buttons["wizard.ready.continue"].isHittable)
        XCTAssertEqual(app.buttons["wizard.ready.continue"].isEnabled, board != "WizardReadyChecking")
        if board == "WizardSaveOffline" {
            XCTAssertTrue(app.staticTexts["wizard.save.offline"].waitUntil(.exists, timeout: 3))
        }
        if board == "WizardSaveServer" {
            XCTAssertTrue(app.staticTexts["wizard.save.server"].waitUntil(.exists, timeout: 3))
        }
    }

    @MainActor private func assertAnswerSheet(_ board: String) {
        let app = WizardScreenUIFlow.launchCompletion(board, language: "nl")
        XCTAssertTrue(app.buttons["wizard.answer.cancel"].waitUntil(.hittable, timeout: 3))
        XCTAssertTrue(app.buttons["wizard.answer.done"].exists)
        if board.hasSuffix("Error") {
            XCTAssertFalse(app.buttons["wizard.answer.done"].isEnabled)
            XCTAssertTrue(app.staticTexts["wizard.answer.error"].exists)
        }
    }
}
