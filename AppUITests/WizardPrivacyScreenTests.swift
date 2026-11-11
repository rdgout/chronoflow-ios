import XCTest

nonisolated final class WizardPrivacyScreenTests: ScreenTestCase {
    override func setUp() async throws {
        try await super.setUp()
        executionTimeAllowance = 60
    }

    @MainActor func testScreeningShowsOnlyTheShiftWorkQuestion() {
        let app = WizardScreenUIFlow.launch("WizardQShift")
        XCTAssertEqual(
            app.staticTexts["wizard.title"].label,
            "In the past 14 days, have you worked night or rotating shifts, or had a very irregular sleep schedule?")
        XCTAssertTrue(app.buttons["wizard.choice.question.false"].isHittable)
        XCTAssertTrue(app.buttons["wizard.choice.question.true"].isHittable)
    }

    @MainActor func testFineTuneShowsNativePreferenceToggles() {
        let app = WizardScreenUIFlow.launch("WizardFineTune")
        XCTAssertTrue(app.switches["wizard.preference.exclude_caffeine"].isHittable)
        let movement = app.switches["wizard.preference.flight_movement_breaks"]
        AuthUIFlow.reveal(movement, in: app)
        XCTAssertTrue(movement.isHittable)
    }

    @MainActor func testLightDeviceSheetHasTheTextOnlyNotice() {
        let app = WizardScreenUIFlow.launch("WizardSheetLight")
        let notice = app.staticTexts["wizard.answer.lightNotice"]
        XCTAssertTrue(notice.waitUntil(.exists, timeout: 3))
        XCTAssertTrue(notice.label.contains("Ask your doctor first."))
    }

    @MainActor func testAudienceNoticeIsNextToWhoThePlannerIsFor() {
        let app = WizardScreenUIFlow.launch("WizardWhere")
        let notice = app.staticTexts["wizard.audienceNotice"]
        AuthUIFlow.reveal(notice, in: app)
        XCTAssertTrue(notice.label.contains("adults with a regular nightly sleep pattern"))
        XCTAssertTrue(notice.label.contains("manic or hypomanic episode"))
    }
}
