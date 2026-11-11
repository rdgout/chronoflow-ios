#if DEBUG
    import DesignSystem
    import LocalStore
    import SwiftUI
    import TripWizard
    import TripWizardUI
    import UIKit
    import XCTest

    @testable import ChronoFlow

    nonisolated final class TripWizardActionsLayoutTests: XCTestCase {
        override func setUp() {
            super.setUp()
            executionTimeAllowance = 60
        }

        @MainActor func testSEEditFooterAtXXLarge() async throws { try await check("se") }
        @MainActor func testDuoEditFooterAtXXLarge() async throws { try await check("duo-asymmetric") }

        @MainActor private func check(_ name: String) async throws {
            try await AuthTestHost.registerFonts()
            let profile = try XCTUnwrap(try AuthDeviceFixture.layoutStressProfiles().first { $0.name == name })
            let database = AccountDatabase(
                applicationSupport: .temporaryDirectory.appendingPathComponent(UUID().uuidString), namespace: .mock)
            try await database.open(accountID: UUID().uuidString)
            do {
                for board in ["WizardEditReturnNoCredits", "WizardEditChanged"] {
                    let model = tripActionBoardModel(board, database: database)
                    let content = PlanMeasuredContent()
                    let host = try AuthTestHost(
                        MemberWizardView(model: model, dismiss: {}).capturePlanContent(in: content),
                        size: profile.size, insets: profile.insets, language: "nl", category: .extraExtraLarge,
                        scale: profile.scale)
                    defer { host.close() }
                    try await host.settleLayout { content.frames }
                    let footer = try XCTUnwrap(content.frame(for: "wizard.ready.footer"))
                    let safe = CGRect(
                        x: profile.insets.left, y: profile.insets.top,
                        width: profile.size.width - profile.insets.left - profile.insets.right,
                        height: profile.size.height - profile.insets.top - profile.insets.bottom)
                    WizardLayoutTestSupport.assertVerticallyContained(
                        footer, in: safe,
                        tolerance: 1 / profile.scale, context: "\(profile.name) \(board)")
                }
                try await database.close()
            } catch {
                try? await database.close()
                throw error
            }
        }
    }

    nonisolated class TripWizardActionsSnapshotTests: XCTestCase {
        var profileName: String { "17e" }
        override func setUp() {
            super.setUp()
            executionTimeAllowance = 60
        }

        @MainActor func testEdit() async throws { try await capture("WizardEdit") }
        @MainActor func testChanged() async throws { try await capture("WizardEditChanged") }
        @MainActor func testNoReturn() async throws { try await capture("WizardEditNoReturn") }
        @MainActor func testReturn() async throws { try await capture("WizardEditReturn") }
        @MainActor func testNoCredits() async throws { try await capture("WizardEditReturnNoCredits") }
        @MainActor func testWeb() async throws { try await capture("WizardEditWeb") }
        @MainActor func testChecking() async throws { try await capture("WizardCheckingEdit") }
        @MainActor func testOffline() async throws { try await capture("WizardCheckOfflineEdit") }
        @MainActor func testServer() async throws { try await capture("WizardCheckServerEdit") }
        @MainActor func testExcluded() async throws { try await capture("WizardExcludedEdit") }
        @MainActor func testDiscard() async throws { try await capture("WizardDiscardEdit") }
        @MainActor func testDuplicate() async throws { try await capture("WizardDuplicate") }

        @MainActor private func capture(_ board: String) async throws {
            try await AuthTestHost.registerFonts()
            let profile = try XCTUnwrap(try AuthDeviceFixture.all().first { $0.name == profileName })
            let database = AccountDatabase(
                applicationSupport: .temporaryDirectory.appendingPathComponent(UUID().uuidString), namespace: .mock)
            try await database.open(accountID: UUID().uuidString)
            do {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for language in ["en", "nl"] {
                        let model = tripActionBoardModel(board, database: database, language: language)
                        let host = try AuthTestHost(
                            MemberWizardView(model: model, dismiss: {}), size: profile.size, insets: profile.insets,
                            style: style, language: language, category: .extraExtraLarge, scale: profile.scale)
                        defer { host.close() }
                        try await host.settle()
                        let attachment = XCTAttachment(image: try host.image())
                        attachment.name = "\(board)-\(profile.snapshotName)-\(language)-\(style.rawValue)-xxLarge"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
                try await database.close()
            } catch {
                try? await database.close()
                throw error
            }
        }
    }

    nonisolated final class TripWizardActionsSESnapshotTests: TripWizardActionsSnapshotTests {
        override var profileName: String { "se" }
    }
    nonisolated final class TripWizardActions17SnapshotTests: TripWizardActionsSnapshotTests {
        override var profileName: String { "17" }
    }
    nonisolated final class TripWizardActionsAirSnapshotTests: TripWizardActionsSnapshotTests {
        override var profileName: String { "air" }
    }
    nonisolated final class TripWizardActions18ProSnapshotTests: TripWizardActionsSnapshotTests {
        override var profileName: String { "18pro" }
    }
    nonisolated final class TripWizardActions18ProMaxSnapshotTests: TripWizardActionsSnapshotTests {
        override var profileName: String { "18promax" }
    }
    nonisolated final class TripWizardActionsDuoSnapshotTests: TripWizardActionsSnapshotTests {
        override var profileName: String { "duo" }
    }

    @MainActor private func tripActionBoardModel(_ board: String, database: AccountDatabase, language: String = "nl")
        -> MemberWizardModel
    {
        let draft = WizardBoardCaptureSeed.draft(
            MemberWizardDraft(), board: board, locale: Locale(identifier: language))
        let model = MemberWizardModel(
            draft: draft, store: MemberWizardStore(database: database),
            search: AirportSearchService(search: { _ in [] }, now: { Date() }, sleep: { _ in }))
        WizardBoardCaptureSeed.freeze(model, board: board)
        return model
    }
#endif
