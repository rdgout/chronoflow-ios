#if DEBUG
    import AppCore
    import DataAccess
    import Foundation
    import Settings
    import UIKit

    nonisolated enum SettingsBoardCaptureFixture {
        static var state: String? {
            guard let raw = ProcessInfo.processInfo.environment["CF_AUTH_TEST_ID"], UUID(uuidString: raw) != nil else {
                return nil
            }
            return ProcessInfo.processInfo.environment["CF_SETTINGS_BOARD_STATE"]
        }
        static func seed(_ original: MockServerState) -> MockServerState {
            guard let state else { return original }
            var result = original
            for id in result.accounts.keys {
                guard var account = result.accounts[id], account.snapshot.email == "demo@example.com" else { continue }
                if ["planUnlimited", "planOffline"].contains(state) {
                    account.snapshot.settings.planCredits = JSONObject([
                        "unlimited": .bool(true), "credits": .number(2),
                    ])
                    account.snapshot.billing = JSONObject([
                        "subscription": .object([
                            "tier": .string("annual"), "paymentFailed": .bool(state == "planUnlimited"),
                            "canResume": .bool(state == "planOffline"), "renewsAt": .string("2026-11-14T00:00:00Z"),
                            "endsAt": .string("2026-11-14T00:00:00Z"),
                        ])
                    ])
                }
                if state == "planCredits" {
                    account.snapshot.billing = JSONObject(["checkout": .object(["status": .string("pending")])])
                }
                if state == "bodyMissing" {
                    account.snapshot.settings.bodyClock["caffeineRuledOut"] = .null
                    account.snapshot.settings.bodyClock["vte"] = .null
                    account.snapshot.settings.bodyClock["shiftWork"] = .null
                    account.snapshot.readiness = JSONObject([
                        "variant": .string("needs-answers"),
                        "missing": .array([
                            .object(["question": .string("caffeine_ruled_out")]), .object(["question": .string("vte")]),
                            .object(["question": .string("shift_work")]),
                        ]), "invalidSections": .array([]),
                    ])
                }
                if state == "bodyExcluded" {
                    account.snapshot.settings.bodyClock["shiftWork"] = .bool(true)
                    account.snapshot.readiness = JSONObject([
                        "variant": .string("excluded"), "missing": .array([]), "invalidSections": .array([]),
                    ])
                }
                result.accounts[id] = account
            }
            return result
        }
        @MainActor static func prepare(_ pages: SettingsPagesModel, enabled: Bool) {
            guard enabled, let state else { return }
            if state == "planLoading" { pages.prepareBoardCapture(loading: true) }
            if state == "accountMissing" { pages.prepareBoardCapture(loading: false) }
        }
        static func beforeSecurity() async throws {
            if state == "promptChecking" { try await Task.sleep(for: .seconds(30)) }
        }
    }
#endif
