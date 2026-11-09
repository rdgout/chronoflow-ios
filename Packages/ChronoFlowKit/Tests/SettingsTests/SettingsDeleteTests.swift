import AppCore
import Settings
import Testing

@Suite @MainActor struct SettingsDeleteTests {
    @Test func exactConfirmationAndPasswordAreRequiredAndCredentialsClearAfterRequest() async {
        var sent: [String] = []
        let model = SettingsDeleteModel { sent.append($0) }
        model.password = "password"
        await model.submit()
        #expect(sent.isEmpty && model.stage == .confirmation)
        model.confirmDeletion()
        model.password = ""
        await model.submit()
        #expect(sent.isEmpty && model.errorKey == "Enter your password.")
        model.password = "password"
        await model.submit()
        #expect(sent == ["password"] && model.stage == .deleted && model.password.isEmpty)
    }
    @Test(arguments: [
        DataFailure.offline,
        .validation(fields: ["password": FieldMessage(key: "The provided password was incorrect.")], status: 422),
        .validation(fields: ["billing": FieldMessage(key: "billing")], status: 422),
        .server(status: 503),
    ])
    func failurePreservesAccountAndConfirmationForRetry(failure: DataFailure) async {
        let model = SettingsDeleteModel { _ in throw failure }
        model.confirmDeletion()
        model.password = "password"
        await model.submit()
        #expect(model.stage == .password && model.password.isEmpty && !model.busy && model.errorKey != nil)
        model.stop()
        #expect(model.password.isEmpty)
    }
}
