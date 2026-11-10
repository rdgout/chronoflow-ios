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
        @MainActor func testWorstCaseFineTuneAndReadyKeepFooterInsideEveryInset() async throws {
            try await AuthTestHost.registerFonts()
            let database = AccountDatabase(
                applicationSupport: .temporaryDirectory.appendingPathComponent(UUID().uuidString), namespace: .mock)
            try await database.open(accountID: UUID().uuidString)
            do {
                for profile in try AuthDeviceFixture.layoutStressProfiles() {
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
                        XCTAssertTrue(
                            safe.insetBy(dx: -1 / profile.scale, dy: -1 / profile.scale).contains(footer),
                            "\(profile.name) \(board) \(footer)")
                        host.close()
                    }
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
                XCTAssertTrue(footer.contains(close), "footer=\(footer) close=\(close)")
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

    nonisolated final class WizardCompletionProfileTests: XCTestCase {
        @MainActor func testAllBoardStatesInEveryProfile() async throws {
            try await AuthTestHost.registerFonts()
            let database = AccountDatabase(
                applicationSupport: .temporaryDirectory.appendingPathComponent(UUID().uuidString), namespace: .mock)
            try await database.open(accountID: UUID().uuidString)
            do {
                for profile in try AuthDeviceFixture.all() where profile.device != nil {
                    for board in completionBoards {
                        for style in [UIUserInterfaceStyle.light, .dark] {
                            for language in ["en", "nl"] {
                                for category in try profile.categories {
                                    let model = completionBoardModel(board, database: database)
                                    let host = try AuthTestHost(
                                        MemberWizardView(model: model, dismiss: {}),
                                        size: profile.size, insets: profile.insets, style: style, language: language,
                                        category: category, scale: profile.scale)
                                    host.window.layer.speed = 0
                                    try await host.settle()
                                    let attachment = XCTAttachment(image: try host.image())
                                    attachment.name =
                                        "\(board)-\(profile.snapshotName)-\(language)-\(style.rawValue)-\(category.rawValue)"
                                    attachment.lifetime = .keepAlways
                                    add(attachment)
                                    host.close()
                                }
                            }
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

    private let completionBoards = [
        "WizardFineTune", "WizardFineTuneBusy", "WizardFineTuneMulti", "WizardFineTuneNone", "WizardFineTuneSleep",
        "WizardSheet", "WizardSheetBlue", "WizardSheetBlueError", "WizardSheetBusy", "WizardSheetCheckout",
        "WizardSheetDrinks", "WizardSheetDrinksError",
        "WizardSheetFreeSleep", "WizardSheetLight", "WizardSheetRoom", "WizardSheetWake", "WizardReady",
        "WizardReadyReturn", "WizardReadyUnlimited",
        "WizardReadyFree", "WizardReadyOneFree", "WizardReadyAdjusted", "WizardReadyNoCredits", "WizardReadyChecking",
        "WizardCalculating", "WizardSaveOffline", "WizardSaveServer",
    ]
#endif
