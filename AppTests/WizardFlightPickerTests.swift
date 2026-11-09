import DesignSystem
import Settings
import SwiftUI
import TripWizard
import UIKit
import XCTest

@testable import TripWizardUI

nonisolated final class WizardFlightPickerTests: XCTestCase {
    @MainActor func testCombinedPickerUsesGraphicalDateAndTimeInFixedZoneAcrossProfiles() async throws {
        try await AuthTestHost.registerFonts()
        let value = try XCTUnwrap(WizardDateTime.date("2040-03-25T02:07"))
        for device in try AuthDeviceFixture.all() {
            let host = try AuthTestHost(
                WizardDateTimeSheet(title: "Departure", localTime: "Time in Amsterdam", value: value) { _ in },
                size: device.size, insets: device.insets, category: .extraExtraLarge)
            defer { host.close() }
            try await host.settle()
            let native = pickers(in: host.controller.view)
            XCTAssertEqual(native.count, 1, device.name)
            let picker = try XCTUnwrap(native.first)
            XCTAssertEqual(picker.preferredDatePickerStyle, .inline, device.name)
            XCTAssertEqual(picker.datePickerMode, .dateAndTime, device.name)
            XCTAssertEqual(try XCTUnwrap(picker.timeZone).secondsFromGMT(for: value), 0, device.name)
            XCTAssertEqual(WizardDateTime.string(picker.date), "2040-03-25T02:07", device.name)
        }
    }

    @MainActor func testNativePickerKeepsTheAppLanguageAndPhoneHourCycle() async throws {
        try await AuthTestHost.registerFonts()
        let device = try XCTUnwrap(try AuthDeviceFixture.all().first)
        let name = "WizardPickerClockTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = SettingsDevicePreferences(defaults: defaults)
        for language in [SettingsDevicePreferences.LanguageChoice.en, .nl] {
            preferences.language = language
            for phoneIdentifier in ["en_US@hours=h23", "nl_NL@hours=h12"] {
                let phone = Locale(identifier: phoneIdentifier)
                let locale = preferences.resolvedLocale(phone: phone)
                let host = try AuthTestHost(
                    WizardDateTimeSheet(title: "Departure", localTime: "Time in Amsterdam", value: Date()) { _ in },
                    size: device.size, insets: device.insets, language: locale.identifier)
                defer { host.close() }
                try await host.settle()
                let picker = try XCTUnwrap(pickers(in: host.controller.view).first)
                let nativeLocale = try XCTUnwrap(picker.locale)
                XCTAssertEqual(nativeLocale.language.languageCode?.identifier, language.rawValue)
                XCTAssertEqual(nativeLocale.hourCycle, phone.hourCycle)
            }
        }
    }

    @MainActor private func pickers(in view: UIView) -> [UIDatePicker] {
        (view as? UIDatePicker).map { [$0] } ?? view.subviews.flatMap { pickers(in: $0) }
    }
}
