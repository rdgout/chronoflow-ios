import AppCore
import DesignSystem
import LocalStore
import SwiftUI
import TripWizard
import UIKit
import XCTest

@testable import TripWizardUI

nonisolated final class WizardFlightPickerIdentityTests: XCTestCase {
    @MainActor func testCompactPickersSurviveValidationEditsAndReflow() async throws {
        try await AuthTestHost.registerFonts()
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = AccountDatabase(applicationSupport: root, namespace: .mock)
        try await database.open(accountID: "019a562b-8000-7000-8000-000000000001")
        let store = MemberWizardStore(database: database)
        var draft = try await store.start()
        draft.form.legs[0].departLocal = "2040-11-10T14:40"
        draft.form.legs[0].arriveLocal = "2040-11-10T11:00"
        let key = "legs.0.arriveLocal"
        draft.fieldErrors[key] = FieldMessage(key: "Check the departure and arrival times.")
        let model = MemberWizardModel(
            draft: draft, store: store,
            search: AirportSearchService(search: { _ in [] }, now: { Date() }, sleep: { _ in }))
        let device = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "17e" })
        let host = try AuthTestHost(
            WizardFlightDateTimeRow(model: model, index: 0, arrival: true), size: device.size, insets: device.insets,
            category: .extraExtraLarge)
        defer { host.close() }
        try await host.settle()
        let original = pickers(in: host.controller.view)
        XCTAssertEqual(original.count, 2)
        let identities = original.map(ObjectIdentifier.init)
        let tints = original.map(\.tintColor)
        for value in ["2040-11-10T09:00", "2040-11-10T09:15", "2040-11-11T09:15"] {
            model.setDateTime(value, index: 0, arrival: true)
            try await host.settle()
            XCTAssertNil(model.draft.fieldErrors[key])
            XCTAssertNotNil(WizardDateTime.date(model.draft.form.legs[0].arriveLocal))
            let current = pickers(in: host.controller.view)
            XCTAssertEqual(current.map(ObjectIdentifier.init), identities)
            XCTAssertEqual(current.map(\.tintColor), tints)
            XCTAssertTrue(current.allSatisfy { $0.preferredDatePickerStyle == .compact })
        }
        for fixture in try AuthDeviceFixture.all() {
            host.window.frame.size = fixture.size
            try await host.settle()
            XCTAssertEqual(pickers(in: host.controller.view).map(ObjectIdentifier.init), identities, fixture.name)
        }
        await model.flush()
        try await database.close()
        try FileManager.default.removeItem(at: root)
    }

    @MainActor private func pickers(in view: UIView) -> [UIDatePicker] {
        (view as? UIDatePicker).map { [$0] } ?? view.subviews.flatMap { pickers(in: $0) }
    }
}
