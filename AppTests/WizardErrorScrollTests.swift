import DesignSystem
import LocalStore
import Observation
import SwiftUI
import TripWizard
import UIKit
import XCTest

@testable import ChronoFlow
@testable import TripWizardUI

nonisolated final class WizardErrorScrollTests: XCTestCase {
    @MainActor func testErrorsScrollAboveContinueAcrossAllProfiles() async throws {
        try await AuthTestHost.registerFonts()
        let directory = URL.temporaryDirectory.appendingPathComponent("WizardScroll-\(UUID().uuidString)")
        let database = AccountDatabase(applicationSupport: directory, namespace: .mock)
        try await database.open(accountID: UUID().uuidString)
        do {
            try await checkProfiles(database: database)
            try await database.close()
        } catch {
            try? await database.close()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        try FileManager.default.removeItem(at: directory)
    }

    @MainActor private func checkProfiles(database: AccountDatabase) async throws {
        let search = AirportSearchService(search: { _ in [] }, now: { Date() }, sleep: { _ in })
        for device in try AuthDeviceFixture.all() {
            for language in ["en", "nl"] {
                for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                    var draft = WizardBoardCaptureSeed.draft(
                        MemberWizardDraft(), board: "WizardOutboundScrollErrors", locale: Locale(identifier: language))
                    let start = draft.form.returnBoundary
                    draft.form.end.kind = "return_legs"
                    draft.form.end.returnFromLeg = start
                    draft.form.legs += draft.form.legs.map { leg in
                        var copy = leg
                        copy.id = UUID().uuidString
                        return copy
                    }
                    draft.form.stays += draft.form.stays
                    draft.fieldErrors["legs.\(start).arriveLocal"] = draft.fieldErrors["legs.0.arriveLocal"]
                    draft.fieldErrors["legs.\(start + 4).departLocal"] = draft.fieldErrors["legs.4.departLocal"]
                    for home in [false, true] {
                        draft.state.step = home ? .returnFlight : .outbound
                        draft.state.returnRouteConfirmed = true
                        let model = MemberWizardModel(
                            draft: draft, store: MemberWizardStore(database: database), search: search)
                        let request = WizardScrollRequest()
                        let content = PlanMeasuredContent()
                        let host = try AuthTestHost(
                            WizardScrollScreen(model: model, request: request).capturePlanContent(
                                in: content),
                            size: device.size, insets: device.insets, language: language, category: category,
                            scale: device.scale)
                        defer { host.close() }
                        try await host.settle()
                        let scroll = try XCTUnwrap(
                            authScrollViews(host.controller.view).first {
                                !$0.isHidden && $0.window != nil
                                    && $0.convert($0.bounds, to: host.window).intersects(host.window.bounds)
                            })
                        let adjusted = scroll.adjustedContentInset
                        scroll.setContentOffset(
                            CGPoint(
                                x: -adjusted.left,
                                y: max(
                                    -adjusted.top, scroll.contentSize.height - scroll.bounds.height + adjusted.bottom)),
                            animated: false)
                        try await host.settle()
                        XCTAssertEqual(content.frames.count, 4)
                        let firstIndex = home ? start : 0
                        let lastIndex = firstIndex + 4
                        let footer = try XCTUnwrap(
                            content.frame(for: home ? "wizard.return-flight.footer" : "wizard.outbound.footer"))
                        let first = try XCTUnwrap(content.frame(for: "wizard.flight.errors.\(firstIndex)"))
                        let lastCard = try XCTUnwrap(content.frame(for: "wizard.flight.\(lastIndex)"))
                        let later = try XCTUnwrap(content.frame(for: "wizard.flight.errors.\(lastIndex)"))
                        let outer = scroll.convert(scroll.bounds, to: host.window)
                        let viewport = CGRect(
                            x: outer.minX + adjusted.left, y: outer.minY + adjusted.top,
                            width: outer.width - adjusted.left - adjusted.right,
                            height: min(outer.maxY - adjusted.bottom, footer.minY) - outer.minY - adjusted.top)
                        let context =
                            "\(device.name) \(language) \(category.rawValue) home=\(home) viewport=\(viewport)"
                        let tolerance: CGFloat = 0.5
                        XCTAssertTrue(
                            lastCard.insetBy(dx: -tolerance, dy: -tolerance).contains(later),
                            "\(context) lastCard=\(lastCard) error=\(later)")
                        XCTAssertLessThanOrEqual(
                            lastCard.maxY, footer.minY + tolerance, "\(context) lastCard=\(lastCard) footer=\(footer)")
                        XCTAssertLessThan(first.maxY, viewport.minY, context)
                        XCTAssertTrue(viewport.insetBy(dx: -tolerance, dy: -tolerance).contains(later), context)
                        request.value += 1
                        try await host.settle()
                        let returned = try XCTUnwrap(content.frame(for: "wizard.flight.errors.\(firstIndex)"))
                        XCTAssertTrue(
                            viewport.insetBy(dx: -tolerance, dy: -tolerance).contains(returned),
                            "\(context) error=\(returned)")
                    }
                }
            }
        }
    }
}

@MainActor @Observable private final class WizardScrollRequest {
    var value = 0
}

private struct WizardScrollScreen: View {
    let model: MemberWizardModel
    let request: WizardScrollRequest

    var body: some View {
        var wizard = MemberWizardView(model: model, dismiss: {})
        wizard.errorScrollOverride = request.value
        return wizard.transaction { $0.disablesAnimations = true }
    }
}
