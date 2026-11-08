import AppCore
import Foundation
import LocalStore
import Settings
import Testing

@Suite @MainActor struct SettingsSecurityTests {
    @Test func passwordValidationAndSubmissionClearCredentialsAndReportOffline() async {
        var calls: [AccountSecurityChange] = []
        let model = SettingsSecurityModel { change in
            calls.append(change)
            throw DataFailure.offline
        }
        model.currentPassword = "old"
        model.newPassword = "New password1!"
        model.confirmation = "different"
        await model.changePassword()
        #expect(calls.isEmpty && model.errors["password_confirmation"] != nil)
        model.confirmation = model.newPassword
        await model.changePassword()
        #expect(calls == [.password(current: "old", password: "New password1!", confirmation: "New password1!")])
        #expect(model.currentPassword.isEmpty && model.newPassword.isEmpty && model.confirmation.isEmpty)
        #expect(model.message == "Needs a connection." && !model.busy)
    }

    @Test func wrongPasswordKeepsPromptOpenAndSetupSurvivesConfirmationFailure() async {
        var stage = 0
        let model = SettingsSecurityModel { change in
            switch change {
            case .enableTwoFactor:
                if stage == 0 {
                    throw DataFailure.validation(
                        fields: ["current_password": FieldMessage(key: "The provided password was incorrect.")],
                        status: 422)
                }
                return .setup(ApiTwoFactorSetup(secretKey: "secret", otpauthUrl: "otpauth://test"))
            case .confirmTwoFactor:
                if stage == 1 { throw DataFailure.server(status: 503) }
                return .codes(ApiRecoveryCodes(recoveryCodes: ["one", "two"]))
            default: return .changed
            }
        }
        model.showPrompt(.enable)
        model.promptPassword = "wrong"
        await model.submitPrompt()
        #expect(model.prompt == .enable && model.promptPassword.isEmpty)
        #expect(model.errors["current_password"] != nil)
        stage = 1
        model.promptPassword = "correct"
        await model.submitPrompt()
        #expect(model.prompt == nil && model.setup?.secretKey == "secret")
        model.code = "1"
        await model.confirm()
        #expect(model.errors["code"] != nil)
        model.code = "123456"
        await model.confirm()
        #expect(model.setup?.secretKey == "secret" && model.codes.isEmpty && model.code.isEmpty)
        stage = 2
        model.code = "123456"
        await model.confirm()
        #expect(model.setup == nil && model.codes == ["one", "two"])
        #expect(model.message == "Two-factor is on. Save your recovery codes now.")
        model.clearSecrets()
        #expect(model.codes.isEmpty && model.setup == nil)
    }

    @Test func throttlingBlocksFurtherRequestsUntilDeadline() async {
        var calls = 0
        let model = SettingsSecurityModel(
            perform: { _ in
                calls += 1
                throw DataFailure.throttled(retryAfterSeconds: 60, status: 429)
            }, now: { Date(timeIntervalSince1970: 100) })
        model.showPrompt(.reveal)
        model.promptPassword = "password"
        await model.submitPrompt()
        #expect(model.locked && model.remaining(at: Date(timeIntervalSince1970: 130)) == 30)
        model.promptPassword = "password"
        await model.submitPrompt()
        #expect(calls == 1)
    }

    @Test func secretsStayOutOfSQLiteAndPendingBodyClockSurvivesSecuritySnapshot() async throws {
        let f = try await SettingsPageFixture.make()
        try await OutboxRepository(database: f.database).enqueue(
            .settings(section: .bodyClock, patch: JSONObject(["age_band": .string("65_plus")])), permit: f.permit)
        let model = SettingsPagesModel(
            database: f.database, permit: f.permit, isCurrent: { true },
            security: { _ in
                .codes(ApiRecoveryCodes(recoveryCodes: ["secret-code"]))
            })
        _ = try await model.performSecurity(.confirmTwoFactor(code: "123456"))
        let rows = try await SettingsRepository(database: f.database).settings()
        #expect(rows.allSatisfy { !$0.value.rawValue.contains("secret-code") && !$0.value.rawValue.contains("123456") })
        #expect(
            try rows.first { $0.section == "security" }?.value.decode(JSONObject.self)["twoFactorEnabled"]
                == .bool(true))
        #expect(try await OutboxRepository(database: f.database).pending().map(\.kind) == ["settings"])
        model.stop()
        await #expect(throws: CancellationError.self) {
            try await model.performSecurity(.enableTwoFactor(current: "password"))
        }
        try await f.close()
    }
}
