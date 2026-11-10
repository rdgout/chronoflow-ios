import AppCore
import Settings
import Testing

@Suite @MainActor struct SettingsDeleteTests {
    @Test func deletionWorksAgainAfterStoppingAndReturning() async {
        var calls = 0
        let model = SettingsDeleteModel { _ in calls += 1 }
        model.confirmDeletion()
        await model.submit()
        #expect(model.errorKey == "Enter your password.")
        model.password = "discard"
        model.stop()
        #expect(model.stage == .confirmation && model.password.isEmpty && model.errorKey == nil && !model.busy)
        model.confirmDeletion()
        model.password = "pw"
        await model.submit()
        #expect(calls == 1 && model.stage == .deleted && !model.busy)
    }

    @Test func lateDeletionCannotFinishANewRequest() async {
        var responses: [CheckedContinuation<Void, Never>] = []
        var started: CheckedContinuation<Void, Never>?
        let model = SettingsDeleteModel { _ in
            await withCheckedContinuation {
                responses.append($0)
                started?.resume()
                started = nil
            }
        }
        model.confirmDeletion()
        model.password = "pw"
        let previous = Task { await model.submit() }
        await withCheckedContinuation { started = $0 }
        model.stop()
        #expect(model.stage == .confirmation && model.password.isEmpty && !model.busy)
        model.confirmDeletion()
        model.password = "pw"
        let current = Task { await model.submit() }
        await withCheckedContinuation { started = $0 }
        responses[0].resume()
        await previous.value
        #expect(model.stage == .password && model.busy)
        responses[1].resume()
        await current.value
        #expect(model.stage == .deleted && !model.busy)
    }

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
