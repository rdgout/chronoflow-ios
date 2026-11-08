import AppCore
import Foundation
import Settings
import Testing

@Suite struct SettingsPlanTests {
    @Test func loadingOfflineAndInvalidBalanceNeverInventCredits() {
        for loaded in [false, true] {
            let state = SettingsPlanState(credits: nil, billing: nil, loaded: loaded, offline: true)
            #expect(state.loaded == loaded && state.offline && !state.hasBalance && state.credits == nil)
        }
        for count in [Decimal(-1), Decimal.nan, Decimal(1.5)] {
            let state = SettingsPlanState(
                credits: JSONObject(["credits": .number(count)]), billing: nil, loaded: true, offline: false)
            #expect(state.credits == nil && !state.hasBalance)
        }
    }
    @Test func cachedCreditsRemainAvailableOfflineAndCancellationUsesServerState() {
        let billing = JSONObject([
            "subscription": .object([
                "canResume": .bool(true), "endsAt": .string("2026-12-01T00:00:00Z"), "paymentFailed": .bool(true),
                "tier": .string("annual"),
            ])
        ])
        let state = SettingsPlanState(
            credits: JSONObject(["credits": .number(7), "unlimited": .bool(false)]), billing: billing, loaded: true,
            offline: true)
        #expect(state.credits == 7 && state.hasBalance && state.offline)
        #expect(
            state.cancelled && state.paymentFailed && state.date == "2026-12-01T00:00:00Z" && state.interval == "yearly"
        )
        let unlimited = SettingsPlanState(
            credits: JSONObject(["unlimited": .bool(true)]), billing: nil, loaded: true, offline: false)
        #expect(unlimited.hasBalance && unlimited.unlimited && unlimited.credits == nil)
    }
}
