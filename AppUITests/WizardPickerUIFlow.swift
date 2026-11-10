import XCTest

@MainActor enum WizardPickerUIFlow {
    static var seededDeparture: Date {
        WizardPickerUIFlow.calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
    }

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
        XCTAssertTrue(picker.waitUntil(.exists, timeout: 5))
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
            XCTAssertTrue(arrow.waitUntil(.exists, timeout: 3), picker.debugDescription)
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
        XCTAssertTrue(day.waitUntil(.exists, timeout: 3), picker.debugDescription)
        day.tap()
    }
}

@MainActor enum WizardScreenUIFlow {
    static func launchCompletion(_ board: String, language: String = "en") -> XCUIApplication {
        launch(board, language: language)
    }

    static func launch(_ board: String, language: String = "en") -> XCUIApplication {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments = AuthUIFlow.arguments(language: language)
        AuthUIFlow.launchSignedIn(
            app, walkthroughSeen: true, extraEnv: ["CF_WIZARD_BOARD_CAPTURE": board, "CF_WIZARD_AUTO_OPEN": "1"])
        XCTAssertTrue(app.staticTexts["wizard.title"].firstMatch.waitUntil(.exists, timeout: 5))
        return app
    }
}
