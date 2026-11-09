import XCTest

@MainActor enum WizardPickerUIFlow {
    static func date(days: Int, from anchor: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: anchor)!
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func open(_ side: String, index: Int = 0, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["wizard.\(index).\(side).date-time"]
        AuthUIFlow.reveal(button, in: app, scroll: app.scrollViews.firstMatch)
        button.tap()
        let picker = app.datePickers["wizard.native-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["wizard.picker.done"].exists)
        XCTAssertTrue(app.buttons["wizard.picker.cancel"].exists)
        return picker
    }

    static func selectDate(_ date: Date, from displayed: Date = Date(), picker: XCUIElement) {
        let from = calendar.dateComponents([.year, .month], from: displayed)
        let to = calendar.dateComponents([.year, .month, .day], from: date)
        let months = (to.year! - from.year!) * 12 + to.month! - from.month!
        if months != 0 {
            let arrow = picker.buttons.matching(
                NSPredicate(
                    format: "label CONTAINS[c] %@", months > 0 ? "Next Month" : "Previous Month")
            ).firstMatch
            XCTAssertTrue(arrow.waitForExistence(timeout: 3), picker.debugDescription)
            for _ in 0..<abs(months) { arrow.tap() }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, d MMMM"
        let british = formatter.string(from: date)
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        let american = formatter.string(from: date)
        let day = picker.buttons.matching(
            NSPredicate(
                format: "label == %@ OR label CONTAINS %@ OR label CONTAINS %@",
                String(to.day!), british, american)
        ).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 3), picker.debugDescription)
        day.tap()
    }

    static func setTime(hour: Int, minute: Int, picker: XCUIElement, in app: XCUIApplication) {
        let time = picker.buttons.matching(NSPredicate(format: "label CONTAINS ':' OR label == 'Time'")).firstMatch
        XCTAssertTrue(time.waitForExistence(timeout: 3), picker.debugDescription)
        time.tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 1).waitForExistence(timeout: 3), app.debugDescription)
        let twelveHour = wheels.count == 3
        wheels.element(boundBy: 0).adjust(
            toPickerWheelValue: twelveHour ? String(hour % 12 == 0 ? 12 : hour % 12) : String(hour))
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: String(format: "%02d", minute))
        if twelveHour { wheels.element(boundBy: 2).adjust(toPickerWheelValue: hour < 12 ? "AM" : "PM") }
        app.navigationBars.staticTexts.matching(NSPredicate(format: "label == 'Departure' OR label == 'Arrival'"))
            .firstMatch.tap()
    }

    static func dateTime(_ side: String, index: Int = 0, date: Date, hour: Int, minute: Int, in app: XCUIApplication) {
        let picker = open(side, index: index, in: app)
        selectDate(date, picker: picker)
        setTime(hour: hour, minute: minute, picker: picker, in: app)
        app.buttons["wizard.picker.done"].tap()
        XCTAssertTrue(app.buttons["wizard.\(index).\(side).date-time"].waitForExistence(timeout: 5))
    }
}

@MainActor enum WizardScreenUIFlow {
    static func launch(_ board: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments(language: language)
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
        app.launchEnvironment["CF_WIZARD_BOARD_CAPTURE"] = board
        app.launch()
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 15))
        app.tabBars.buttons[language == "nl" ? "Mijn reizen" : "My trips"].tap()
        let create = app.buttons["trips.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        XCTAssertTrue(app.descendants(matching: .any)["wizard.title"].waitForExistence(timeout: 8))
        return app
    }
}
