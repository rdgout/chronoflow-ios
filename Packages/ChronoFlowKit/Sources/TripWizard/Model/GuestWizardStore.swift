import AppCore
import Foundation

public actor GuestWizardStore: WizardDraftStore {
    private struct Record: Codable {
        var form: WizardForm
        var state: MemberWizardState
        var fieldErrors: [String: FieldMessage]
        var updatedAt: String
    }

    private let url: URL
    private let now: @Sendable () -> Date

    public init(
        applicationSupport: URL, namespace: StorageNamespace,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        url = GuestRecoveryLocation.file(applicationSupport: applicationSupport, namespace: namespace)
        self.now = now
    }

    public func start() throws -> MemberWizardDraft {
        if let draft = try recover() { return draft }
        var draft = MemberWizardDraft()
        draft.state.mode = .guest
        draft.state.lastInputStep = .sleep
        draft.state.firstTrip = false
        draft.state.profile = JSONObject(["habitual_bed": .string("23:00"), "habitual_wake": .string("07:00")])
        try write(record(draft))
        return draft
    }

    public func recover() throws -> MemberWizardDraft? {
        guard let record = try recoverRecord() else { return nil }
        return MemberWizardDraft(
            form: record.form, state: record.state, airports: record.state.airports, fieldErrors: record.fieldErrors)
    }

    public func recoveryDecision(handoffFinished: Bool, introFinished: Bool) throws -> GuestRecoveryGate.Decision {
        guard let record = try recoverRecord() else { return .none }
        return GuestRecoveryGate.decision(
            updatedAt: Self.formatter().date(from: record.updatedAt), now: now(),
            handoffFinished: handoffFinished, introFinished: introFinished, signingIn: record.state.signingIn == true)
    }

    private func recoverRecord() throws -> Record? {
        assert(!Thread.isMainThread)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let record: Record
        do {
            record = try JSONDecoder().decode(Record.self, from: ProfilePreferences.cleanLegacyJSON(data))
        } catch {
            try remove()
            return nil
        }
        let formatter = Self.formatter()
        guard let updated = formatter.date(from: record.updatedAt),
            GuestRecoveryGate.decision(
                updatedAt: updated, now: now(), handoffFinished: false, introFinished: false,
                signingIn: record.state.signingIn == true) != .expire,
            !record.form.legs.isEmpty, record.form.legs.count <= WizardForm.maxFlights,
            record.form.stays.count == record.form.legs.count, record.form.end.kind == "one_way"
        else {
            try remove()
            return nil
        }
        let cleaned = self.record(
            MemberWizardDraft(
                form: record.form, state: record.state, airports: record.state.airports,
                fieldErrors: record.fieldErrors), updatedAt: record.updatedAt)
        try write(cleaned)
        return cleaned
    }

    public func persist(_ draft: MemberWizardDraft) throws {
        guard let current = try recover(), current.state.instance == draft.state.instance else {
            throw CancellationError()
        }
        guard current.state.revision <= draft.state.revision else { return }
        try write(record(draft))
    }

    public func discard(instance: String) throws {
        guard try recover()?.state.instance == instance else { return }
        try remove()
    }

    public func didSave(instance: String, firstTrip: Bool) throws { try discard(instance: instance) }

    public func claim(secrets: any GuestSecretStore) async -> GuestClaim? {
        guard let draft = try? recover(), let identity = draft.form.identity, !identity.token.isEmpty,
            let revision = identity.reviewRevision,
            let secret = try? await secrets.get(for: identity.token), !secret.isEmpty,
            let current = try? recover(), current.state.instance == draft.state.instance,
            current.form.identity == identity
        else { return nil }
        return GuestClaim(
            draftToken: identity.token, inputRevision: identity.inputRevision, reviewRevision: revision,
            guestSecret: secret)
    }

    public func reviewExpired(claim: GuestClaim) throws {
        guard var draft = try recover(), draft.form.identity?.token == claim.draftToken,
            draft.form.identity?.inputRevision == claim.inputRevision,
            draft.form.identity?.reviewRevision == claim.reviewRevision
        else { return }
        draft.returnToReadyAfterExpiredClaim()
        draft.state.revision += 1
        try persist(draft)
    }

    private func record(_ draft: MemberWizardDraft, updatedAt: String? = nil) -> Record {
        var form = draft.form
        var state = draft.state
        form.identity?.guestSecret = nil
        state.review?.identity.guestSecret = nil
        state.mode = .guest
        state.lastInputStep = .sleep
        state.sleepNeeded = true
        state.savedProfile = nil
        state.firstTrip = false
        state.discardRetiredValues()
        return Record(
            form: form, state: state, fieldErrors: draft.fieldErrors,
            updatedAt: updatedAt ?? Self.formatter().string(from: now()))
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }

    private func write(_ record: Record) throws {
        assert(!Thread.isMainThread)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try ProfilePreferences.cleanLegacyJSON(JSONEncoder().encode(record))
        #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
            try data.write(to: url, options: .atomic)
        #endif
        var file = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }

    private func remove() throws {
        assert(!Thread.isMainThread)
        try FileManager.default.removeItem(at: url)
    }
}
