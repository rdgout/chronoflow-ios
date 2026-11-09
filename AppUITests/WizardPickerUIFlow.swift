import XCTest

@MainActor enum WizardPickerUIFlow {
    static func date(days: Int, from anchor: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(byAdding: .day, value: days, to: anchor)!
    }

    static func emptyDate(_ side: String, index: Int = 0, date: Date, in app: XCUIApplication) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: date)
        formatter.dateFormat = "d"
        let day = formatter.string(from: date)
        formatter.dateFormat = "yyyy"
        let year = formatter.string(from: date)
        let button = app.buttons["wizard.\(index).\(side).date"]
        AuthUIFlow.reveal(button, in: app, scroll: app.scrollViews.firstMatch)
        button.tap()
        // Empty pills open our wheel popover; populated compact date pickers open the system calendar.
        XCTAssertTrue(app.datePickers["wizard.native-picker"].waitForExistence(timeout: 5))
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 2).waitForExistence(timeout: 5))
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: "1")
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: year)
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: month)
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: day)
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
