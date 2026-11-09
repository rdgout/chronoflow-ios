import XCTest

@MainActor enum WizardPickerUIFlow {
    static func emptyDate(
        _ side: String, index: Int = 0, month: String = "November", day: String, year: String = "2040",
        in app: XCUIApplication
    ) {
        let button = app.buttons["wizard.\(index).\(side).date"]
        AuthUIFlow.reveal(button, in: app, scroll: app.scrollViews.firstMatch)
        button.tap()
        // Empty pills open our wheel popover; populated compact date pickers open the system calendar.
        XCTAssertTrue(app.datePickers["wizard.native-picker"].waitForExistence(timeout: 5))
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 2).waitForExistence(timeout: 5))
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: month)
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: day)
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: year)
        app.buttons["wizard.picker.done"].tap()
        XCTAssertTrue(app.datePickers["wizard.\(index).\(side).date"].waitForExistence(timeout: 5))
    }

    static func time(_ side: String, index: Int = 0, hour: String, minute: String, in app: XCUIApplication) {
        let picker = app.datePickers["wizard.\(index).\(side).time"]
        AuthUIFlow.reveal(picker, in: app, scroll: app.scrollViews.firstMatch)
        picker.tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 1).waitForExistence(timeout: 5))
        let twelveHour = wheels.count == 3
        let numeric = Int(hour)!
        wheels.element(boundBy: 0).adjust(
            toPickerWheelValue: twelveHour ? String(numeric % 12 == 0 ? 12 : numeric % 12) : hour)
        XCTAssertTrue(
            wheels.element(boundBy: 1).waitForExistence(timeout: 3),
            "Compact time popover dismissed after changing the hour")
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: minute)
        if twelveHour {
            XCTAssertTrue(wheels.element(boundBy: 2).waitForExistence(timeout: 3))
            wheels.element(boundBy: 2).adjust(toPickerWheelValue: numeric < 12 ? "AM" : "PM")
        }
        app.staticTexts[index == 0 ? "When is your flight?" : "Your flight home"].tap()
        XCTAssertTrue(picker.exists)
    }
}
