import AppCore
import Auth
import Foundation
import Settings
import Testing

@testable import DataAccess

@Suite @MainActor struct SettingsPasskeysTests {
    @MainActor private final class Server {
        var passkeys = [
            ApiPasskey(id: 1, name: "iPhone 16", createdAt: "2026-09-14T08:00:00.000000Z"),
            ApiPasskey(id: 2, name: "MacBook Pro", createdAt: "2026-10-02T08:00:00.000000Z"),
        ]
        var calls: [AccountSecurityChange] = []
        var failure: DataFailure?
        var failsOnAdd = false
        var failsOnOptions = false
        var optionsChallenge = "Y2g"
        func perform(_ change: AccountSecurityChange) async throws -> AccountSecurityResult {
            calls.append(change)
            if let failure, failsOnOptions ? isOptions(change) : failsOnAdd ? isAdd(change) : !isList(change) {
                throw failure
            }
            if let failure, isList(change), case .offline = failure { throw failure }
            switch change {
            case .listPasskeys: return .passkeys(passkeys)
            case .passkeyCreationOptions:
                return .passkeyCreation(
                    ApiPasskeyRegistrationChallenge(
                        challengeId: "c1",
                        options: ApiPasskeyCreationOptions(
                            challenge: optionsChallenge, rp: ApiPasskeyRelyingParty(id: "app.chronoflow.net"),
                            user: ApiPasskeyUserEntity(id: "dXNlcg", name: "demo@example.com"))))
            case .addPasskey(let input):
                let item = ApiPasskey(id: 3, name: input.name, createdAt: "2026-11-12T09:30:00.000000Z")
                passkeys.insert(item, at: 0)
                return .passkeyAdded(item)
            case .removePasskey(let id, _):
                passkeys.removeAll { $0.id == id }
                return .changed
            default: throw DataFailure.unsupported(.security)
            }
        }
        private func isAdd(_ change: AccountSecurityChange) -> Bool {
            if case .addPasskey = change { return true }
            return false
        }
        private func isOptions(_ change: AccountSecurityChange) -> Bool {
            if case .passkeyCreationOptions = change { return true }
            return false
        }
        private func isList(_ change: AccountSecurityChange) -> Bool {
            if case .listPasskeys = change { return true }
            return false
        }
        var optionsPassword: String? {
            for case .passkeyCreationOptions(let current) in calls { return current }
            return nil
        }
        var added: ApiPasskeyRegistrationInput? {
            for case .addPasskey(let input) in calls { return input }
            return nil
        }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_000)
        var now: Date { lock.withLock { date } }
        func advance(_ seconds: TimeInterval) { lock.withLock { date += seconds } }
    }

    private func model(
        _ server: Server, provider: (any PasskeyRegistrationProviding)? = DeterministicRegistrationProvider()
    ) -> SettingsSecurityModel {
        SettingsSecurityModel(
            perform: { try await server.perform($0) }, registration: provider, deviceName: "Rick's iPhone")
    }

    @Test func loadShowsTheListAndAnEmptyAccount() async {
        let server = Server()
        let model = model(server)
        #expect(model.passkeys == nil && !model.passkeysUnavailable)
        await model.loadPasskeys()
        #expect(model.passkeys?.map(\.name) == ["iPhone 16", "MacBook Pro"])
        server.passkeys = []
        await model.loadPasskeys()
        #expect(model.passkeys == [])
    }

    @Test func offlineLoadIsRetryableAndKeepsAnExistingListOnLaterFailure() async {
        let server = Server()
        server.failure = .offline
        let model = model(server)
        await model.loadPasskeys()
        #expect(model.passkeys == nil && model.passkeysUnavailable && model.offline)
        server.failure = nil
        await model.loadPasskeys()
        #expect(model.passkeys?.count == 2 && !model.passkeysUnavailable && !model.offline)
        server.failure = .offline
        await model.loadPasskeys()
        #expect(model.passkeys?.count == 2 && !model.passkeysUnavailable && model.offline)
    }

    @Test func addChecksThePasswordAtOptionsThenRegistersWithTheDeviceNameAndRefreshesTheList() async {
        let server = Server()
        let model = model(server)
        await model.loadPasskeys()
        model.showPrompt(.addPasskey)
        model.promptPassword = "pw"
        await model.submitPrompt()
        let input = server.added
        #expect(server.optionsPassword == "pw")
        #expect(input?.name == "Rick's iPhone" && input?.challengeId == "c1")
        #expect(input?.credential.response.transports == ["internal"])
        #expect(model.prompt == nil && model.message == "Passkey added" && model.errors.isEmpty)
        #expect(model.promptPassword.isEmpty && model.passkeys?.count == 3 && !model.busy)
        #expect(model.passkeys?.first?.id == 3)
    }

    @Test func cancellingTheSystemSheetShowsNoErrorAndKeepsThePromptReady() async {
        let server = Server()
        let model = model(server, provider: DeterministicRegistrationProvider { _ in throw PasskeyFailure.canceled })
        model.showPrompt(.addPasskey)
        model.promptPassword = "pw"
        await model.submitPrompt()
        #expect(model.message == nil && model.errors.isEmpty && !model.busy)
        #expect(model.prompt == .addPasskey && model.promptPassword == "pw")
        #expect(server.added == nil)
    }

    @MainActor private final class CallCounter {
        var providerCalls = 0
    }

    @Test(arguments: [0, 1, 2])
    func registrationFailuresShowTheRegistrationMessageAndSendNothing(_ fault: Int) async {
        let server = Server()
        let counter = CallCounter()
        var provider: (any PasskeyRegistrationProviding)? = DeterministicRegistrationProvider { challenge in
            counter.providerCalls += 1
            if fault == 0 { throw PasskeyFailure.unavailable }
            return Base64URL.attestation(
                credentialID: Data([1]), clientDataJSON: Data([2]), attestationObject: Data([3]), transports: [])
        }
        if fault == 1 { server.optionsChallenge = "not base64url!" }
        if fault == 2 { provider = nil }
        let model = model(server, provider: provider)
        model.showPrompt(.addPasskey)
        model.promptPassword = "pw"
        await model.submitPrompt()
        #expect(model.message == "We couldn't register that passkey. Please try again.")
        #expect(model.prompt == nil && model.errors.isEmpty && server.added == nil && !model.busy)
        #expect(counter.providerCalls == (fault == 0 ? 1 : 0))
    }

    @Test func serverRejectionOfTheCredentialShowsTheSameMessage() async {
        let server = Server()
        let model = model(server)
        model.showPrompt(.addPasskey)
        model.promptPassword = "pw"
        server.failsOnAdd = true
        server.failure = .validation(
            fields: ["credential": FieldMessage(key: "We couldn't register that passkey. Please try again.")],
            status: 422)
        await model.submitPrompt()
        #expect(server.added != nil)
        #expect(model.message == "We couldn't register that passkey. Please try again." && model.prompt == nil)
        #expect(model.errors.isEmpty && model.promptPassword.isEmpty && !model.busy)
    }

    @Test func wrongPasswordFailsAtOptionsBeforeTheSystemSheetAndStaysInThePrompt() async {
        let server = Server()
        let counter = CallCounter()
        let model = model(
            server,
            provider: DeterministicRegistrationProvider { _ in
                counter.providerCalls += 1
                throw PasskeyFailure.unavailable
            })
        model.showPrompt(.addPasskey)
        model.promptPassword = "bad"
        server.failsOnOptions = true
        server.failure = .validation(
            fields: ["current_password": FieldMessage(key: "The provided password was incorrect.")], status: 422)
        await model.submitPrompt()
        #expect(server.optionsPassword == "bad" && server.added == nil && counter.providerCalls == 0)
        #expect(model.prompt == .addPasskey && model.message == nil)
        #expect(model.errors["current_password"] == "The provided password was incorrect.")
        #expect(model.promptPassword.isEmpty)
    }

    @Test func expiredChallengeShowsTheExpiryMessageAndClosesThePrompt() async {
        let server = Server()
        let model = model(server)
        model.showPrompt(.addPasskey)
        model.promptPassword = "pw"
        server.failsOnAdd = true
        server.failure = .validation(
            fields: [
                "challengeId": FieldMessage(key: "The passkey registration request expired. Please try again.")
            ], status: 422)
        await model.submitPrompt()
        #expect(model.message == "The passkey registration request expired. Please try again.")
        #expect(model.prompt == nil && model.errors.isEmpty && !model.busy)
    }

    @Test func offlineAddKeepsThePromptAndDisablesFurtherAdds() async {
        let server = Server()
        let model = model(server)
        model.showPrompt(.addPasskey)
        model.promptPassword = "pw"
        server.failsOnAdd = true
        server.failure = .offline
        await model.submitPrompt()
        #expect(server.added != nil)
        #expect(model.message == "Needs a connection." && model.offline && model.prompt == .addPasskey)
        #expect(model.errors.isEmpty && !model.busy)
    }

    @Test func addThrottleLocksAfterTheCredentialWasSent() async {
        let server = Server()
        let model = model(server)
        model.showPrompt(.addPasskey)
        model.promptPassword = "pw"
        server.failsOnAdd = true
        server.failure = .throttled(retryAfterSeconds: 30, status: 429)
        await model.submitPrompt()
        #expect(server.added != nil)
        #expect(model.locked && model.message == "Too many attempts." && model.prompt == .addPasskey)
    }

    @Test func removeSendsThePasswordDropsTheRowAndRefreshes() async {
        let server = Server()
        let model = model(server)
        await model.loadPasskeys()
        let target = ApiPasskey(id: 1, name: "iPhone 16", createdAt: "2026-09-14T08:00:00Z")
        model.showPrompt(.removePasskey, removing: target)
        #expect(model.removal == target)
        model.promptPassword = "pw"
        await model.submitPrompt()
        #expect(server.calls.contains(.removePasskey(id: 1, current: "pw")))
        #expect(model.passkeys?.map(\.id) == [2] && model.prompt == nil && model.removal == nil)
        #expect(model.message == "Passkey removed" && model.promptPassword.isEmpty)
    }

    @Test func removeThrottleLocksUntilTheCountdownEnds() async {
        let server = Server()
        let clock = Clock()
        let model = SettingsSecurityModel(perform: { try await server.perform($0) }, now: { clock.now })
        await model.loadPasskeys()
        model.showPrompt(
            .removePasskey, removing: ApiPasskey(id: 1, name: "iPhone 16", createdAt: "2026-09-14T08:00:00Z"))
        model.promptPassword = "pw"
        server.failure = .throttled(retryAfterSeconds: 30, status: 429)
        await model.submitPrompt()
        #expect(model.locked && model.message == "Too many attempts." && model.passkeys?.count == 2)
        let calls = server.calls.count
        model.promptPassword = "pw"
        await model.submitPrompt()
        #expect(server.calls.count == calls)
        clock.advance(31)
        model.refreshLock()
        #expect(!model.locked)
    }

    @Test func removeWrongPasswordKeepsTheRowAndThePrompt() async {
        let server = Server()
        let model = model(server)
        await model.loadPasskeys()
        model.showPrompt(
            .removePasskey, removing: ApiPasskey(id: 1, name: "iPhone 16", createdAt: "2026-09-14T08:00:00Z"))
        model.promptPassword = "bad"
        server.failure = .validation(
            fields: ["current_password": FieldMessage(key: "The provided password was incorrect.")], status: 422)
        await model.submitPrompt()
        #expect(model.prompt == .removePasskey && model.passkeys?.count == 2)
        #expect(model.errors["current_password"] == "The provided password was incorrect.")
    }

    @Test func leavingTheScreenClearsThePromptAndPasswords() async {
        let server = Server()
        let model = model(server)
        model.showPrompt(
            .removePasskey, removing: ApiPasskey(id: 1, name: "iPhone 16", createdAt: "2026-09-14T08:00:00Z"))
        model.promptPassword = "pw"
        model.clearSecrets()
        #expect(model.prompt == nil && model.removal == nil && model.promptPassword.isEmpty)
    }

    @Test func rowsShowDatesInTheBoardFormat() throws {
        let locale = Locale(identifier: "en_GB")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-12T12:00:00Z"))
        func meta(_ passkey: ApiPasskey, _ language: Language = .en) -> String? {
            SettingsPasskeyText.meta(
                passkey, language: language, locale: language == .nl ? Locale(identifier: "nl_NL") : locale, now: now,
                calendar: calendar)
        }
        #expect(
            meta(ApiPasskey(id: 1, name: "a", createdAt: "2026-10-02T10:00:00Z", lastUsedAt: "2026-11-12T08:00:00Z"))
                == "Added 2 Oct 2026 · used today")
        #expect(
            meta(
                ApiPasskey(
                    id: 2, name: "b", createdAt: "2026-10-02T10:00:00.000000Z", lastUsedAt: "2026-10-28T08:00:00Z"))
                == "Added 2 Oct 2026 · used 28 Oct")
        #expect(meta(ApiPasskey(id: 3, name: "c", createdAt: "2026-10-02T10:00:00Z")) == "Added 2 Oct 2026")
        #expect(
            meta(
                ApiPasskey(id: 6, name: "f", createdAt: "2026-10-02T10:00:00Z", lastUsedAt: "2026-11-12T08:00:00Z"), .nl
            )
                == "Toegevoegd 2 okt 2026 · gebruikt vandaag")
    }

    @Test func listingStoresThePasskeyCountThatGatesTheSecurityRow() async throws {
        let f = try await SettingsPageFixture.make()
        let pages = SettingsPagesModel(
            database: f.database, permit: f.permit, isCurrent: { true },
            security: { change in
                guard case .listPasskeys = change else { throw DataFailure.unsupported(.security) }
                return .passkeys([ApiPasskey(id: 1, name: "iPhone", createdAt: "2026-09-14T08:00:00Z")])
            })
        pages.start()
        defer { pages.stop() }
        _ = try await pages.performSecurity(.listPasskeys)
        try await f.waitUntil { pages.settings["security"]?["passkeyCount"]?.int == 1 }
        try await f.close()
    }

    @Test func countUsesThePluralCatalogInBothLanguages() {
        #expect(SettingsPasskeyText.count(1, language: .en) == "1 passkey")
        #expect(SettingsPasskeyText.count(2, language: .en) == "2 passkeys")
        #expect(SettingsPasskeyText.count(0, language: .nl) == "0 passkeys")
        #expect(SettingsPasskeyText.count(1, language: .nl) == "1 passkey")
    }
}
