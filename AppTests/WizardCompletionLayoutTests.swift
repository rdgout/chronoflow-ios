#if DEBUG
    import DesignSystem
    import LocalStore
    import SwiftUI
    import TripWizard
    import TripWizardUI
    import UIKit
    import XCTest

    @testable import ChronoFlow

    nonisolated final class WizardCompletionLayoutTests: XCTestCase {
        override func setUp() {
            super.setUp()
            executionTimeAllowance = 60
        }

        @MainActor func testWorstCaseFineTuneAndReadySE() async throws { try await checkWorstCase("se") }
        @MainActor func testWorstCaseFineTuneAndReadyDuo() async throws { try await checkWorstCase("duo-asymmetric") }

        @MainActor private func checkWorstCase(_ name: String) async throws {
            let profile = try XCTUnwrap(try AuthDeviceFixture.layoutStressProfiles().first { $0.name == name })
            try await AuthTestHost.registerFonts()
            let database = AccountDatabase(
                applicationSupport: .temporaryDirectory.appendingPathComponent(UUID().uuidString), namespace: .mock)
            try await database.open(accountID: UUID().uuidString)
            do {
                for board in [
                    "WizardFineTuneMulti", "WizardFineTuneSleep", "WizardReadyReturn", "WizardReadyAdjusted",
                    "WizardReadyNoCredits",
                ] {
                    let model = completionBoardModel(board, database: database)
                    let content = PlanMeasuredContent()
                    let host = try AuthTestHost(
                        MemberWizardView(model: model, dismiss: {}).capturePlanContent(in: content),
                        size: profile.size, insets: profile.insets, language: "nl", category: .extraExtraLarge,
                        scale: profile.scale)
                    try await host.settleLayout { content.frames }
                    let step = board.hasPrefix("WizardReady") ? "ready" : "fine-tune"
                    let footer = try XCTUnwrap(content.frame(for: "wizard.\(step).footer"))
                    let safe = CGRect(
                        x: profile.insets.left, y: profile.insets.top,
                        width: profile.size.width - profile.insets.left - profile.insets.right,
                        height: profile.size.height - profile.insets.top - profile.insets.bottom)
                    WizardLayoutTestSupport.assertVerticallyContained(
                        footer, in: safe, tolerance: 1 / profile.scale, context: "\(profile.name) \(board) \(footer)")
                    if board == "WizardReadyNoCredits" {
                        let close = try XCTUnwrap(content.frame(for: "wizard.ready.no-credits"))
                        WizardLayoutTestSupport.assertVerticallyContained(
                            close, in: footer, context: "\(profile.name) footer=\(footer) close=\(close)")
                        XCTAssertLessThan(close.height, footer.height)
                    }
                    host.close()
                }
                try await database.close()
            } catch {
                try? await database.close()
                throw error
            }
        }

        @MainActor func testNoCreditsCloseStaysInsideThePinnedFooterAboveTheHomeIndicator() async throws {
            try await AuthTestHost.registerFonts()
            let database = AccountDatabase(
                applicationSupport: .temporaryDirectory.appendingPathComponent(UUID().uuidString), namespace: .mock)
            try await database.open(accountID: UUID().uuidString)
            do {
                let profile = try XCTUnwrap(try AuthDeviceFixture.all().first { $0.name == "17e" })
                let model = completionBoardModel("WizardReadyNoCredits", database: database)
                let content = PlanMeasuredContent()
                let host = try AuthTestHost(
                    MemberWizardView(model: model, dismiss: {}).capturePlanContent(in: content),
                    size: profile.size, insets: profile.insets, language: "nl", category: .extraExtraLarge,
                    scale: profile.scale)
                defer { host.close() }
                try await host.settleLayout { content.frames }
                let footer = try XCTUnwrap(content.frame(for: "wizard.ready.footer"))
                let close = try XCTUnwrap(content.frame(for: "wizard.ready.no-credits"))
                WizardLayoutTestSupport.assertVerticallyContained(
                    close, in: footer, context: "footer=\(footer) close=\(close)")
                XCTAssertLessThan(close.height, footer.height)
                XCTAssertLessThanOrEqual(close.maxY, profile.size.height - profile.insets.bottom)
                try await database.close()
            } catch {
                try? await database.close()
                throw error
            }
        }

        @MainActor func testDuoResizeKeepsFineTuneAndOpenAnswer() async throws {
            let database = AccountDatabase(
                applicationSupport: .temporaryDirectory.appendingPathComponent(UUID().uuidString), namespace: .mock)
            try await database.open(accountID: UUID().uuidString)
            let model = completionBoardModel("WizardSheetBlue", database: database)
            let sheet = model.draft.state.promptSheetID
            let duo = try XCTUnwrap(try AuthDeviceFixture.all().first { $0.name == "duo" })
            let folded = try XCTUnwrap(try AuthDeviceFixture.all().first { $0.name == "17e" })
            let host = try AuthTestHost(
                MemberWizardView(model: model, dismiss: {}), size: duo.size, insets: duo.insets, language: "nl",
                scale: duo.scale)
            defer { host.close() }
            try await host.settle()
            for size in [folded.size, duo.size] {
                host.window.frame.size = size
                host.window.setNeedsLayout()
                host.window.layoutIfNeeded()
                try await host.settle()
                XCTAssertEqual(model.draft.state.step, .fineTune)
                XCTAssertEqual(model.draft.state.promptSheetID, sheet)
            }
            try await database.close()
        }
    }

    nonisolated class WizardCompletionProfileTests: XCTestCase {
        var profileName: String { "17e" }

        override func setUp() {
            super.setUp()
            executionTimeAllowance = 60
        }

        @MainActor func testFineTune() async throws { try await capture("WizardFineTune") }
        @MainActor func testFineTuneBusy() async throws { try await capture("WizardFineTuneBusy") }
        @MainActor func testFineTuneMulti() async throws { try await capture("WizardFineTuneMulti") }
        @MainActor func testFineTuneNone() async throws { try await capture("WizardFineTuneNone") }
        @MainActor func testFineTuneSleep() async throws { try await capture("WizardFineTuneSleep") }
        @MainActor func testSheet() async throws { try await capture("WizardSheet") }
        @MainActor func testSheetBlue() async throws { try await capture("WizardSheetBlue") }
        @MainActor func testSheetBlueError() async throws { try await capture("WizardSheetBlueError") }
        @MainActor func testSheetBusy() async throws { try await capture("WizardSheetBusy") }
        @MainActor func testSheetCheckout() async throws { try await capture("WizardSheetCheckout") }
        @MainActor func testSheetDrinks() async throws { try await capture("WizardSheetDrinks") }
        @MainActor func testSheetDrinksError() async throws { try await capture("WizardSheetDrinksError") }
        @MainActor func testSheetFreeSleep() async throws { try await capture("WizardSheetFreeSleep") }
        @MainActor func testSheetLight() async throws { try await capture("WizardSheetLight") }
        @MainActor func testSheetRoom() async throws { try await capture("WizardSheetRoom") }
        @MainActor func testSheetWake() async throws { try await capture("WizardSheetWake") }
        @MainActor func testReady() async throws { try await capture("WizardReady") }
        @MainActor func testReadyReturn() async throws { try await capture("WizardReadyReturn") }
        @MainActor func testReadyUnlimited() async throws { try await capture("WizardReadyUnlimited") }
        @MainActor func testReadyFree() async throws { try await capture("WizardReadyFree") }
        @MainActor func testReadyOneFree() async throws { try await capture("WizardReadyOneFree") }
        @MainActor func testReadyAdjusted() async throws { try await capture("WizardReadyAdjusted") }
        @MainActor func testReadyNoCredits() async throws { try await capture("WizardReadyNoCredits") }
        @MainActor func testReadyChecking() async throws { try await capture("WizardReadyChecking") }
        @MainActor func testCalculating() async throws { try await capture("WizardCalculating") }
        @MainActor func testSaveOffline() async throws { try await capture("WizardSaveOffline") }
        @MainActor func testSaveServer() async throws { try await capture("WizardSaveServer") }

        @MainActor private func capture(_ board: String) async throws {
            let profile = try WizardLayoutTestSupport.profile(profileName)
            try await AuthTestHost.registerFonts()
            let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let database = AccountDatabase(applicationSupport: directory, namespace: .mock)
            try await database.open(accountID: UUID().uuidString)
            do {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for language in ["en", "nl"] {
                        for category in try profile.categories {
                            let model = completionBoardModel(board, database: database)
                            let host = try AuthTestHost(
                                MemberWizardView(model: model, dismiss: {}),
                                size: profile.size, insets: profile.insets, style: style, language: language,
                                category: category, scale: profile.scale)
                            defer { host.close() }
                            host.window.layer.speed = 0
                            try await host.settle()
                            let attachment = XCTAttachment(image: try host.image())
                            attachment.name =
                                "\(board)-\(profile.snapshotName)-\(language)-\(style.rawValue)-\(category.rawValue)"
                            attachment.lifetime = .keepAlways
                            add(attachment)
                        }
                    }
                }
                try await database.close()
            } catch {
                try? await database.close()
                throw error
            }
        }
    }

    nonisolated final class WizardCompletionSEProfileTests: WizardCompletionProfileTests {
        override var profileName: String { "se" }
    }

    nonisolated final class WizardCompletion17ProfileTests: WizardCompletionProfileTests {
        override var profileName: String { "17" }
    }

    nonisolated final class WizardCompletionAirProfileTests: WizardCompletionProfileTests {
        override var profileName: String { "air" }
    }

    nonisolated final class WizardCompletion18ProProfileTests: WizardCompletionProfileTests {
        override var profileName: String { "18pro" }
    }

    nonisolated final class WizardCompletion18ProMaxProfileTests: WizardCompletionProfileTests {
        override var profileName: String { "18promax" }
    }

    nonisolated final class WizardCompletionDuoProfileTests: WizardCompletionProfileTests {
        override var profileName: String { "duo" }
    }

    @MainActor private func completionBoardModel(_ board: String, database: AccountDatabase) -> MemberWizardModel {
        let draft = WizardBoardCaptureSeed.draft(MemberWizardDraft(), board: board, locale: Locale(identifier: "nl"))
        let model = MemberWizardModel(
            draft: draft, store: MemberWizardStore(database: database),
            search: AirportSearchService(search: { _ in [] }, now: { Date() }, sleep: { _ in }))
        model.freezeCompletionBoard(
            reviewing: board == "WizardFineTuneBusy" || board == "WizardReadyChecking",
            answerError: board == "WizardSheetBlueError"
                ? "Enter a rating between 0.1 and 9.9."
                : board == "WizardSheetDrinksError" ? "Add at least one drink to save this answer." : nil)
        return model
    }

#endif
