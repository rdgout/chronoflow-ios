import AppCore
import Foundation
import LocalStore
import Observation
import Reminders

@MainActor @Observable public final class RemindersModel {
    public private(set) var settings: ReminderSettings?
    public private(set) var permission: ReminderPermission?
    public private(set) var busy = false
    public private(set) var failure: (any Error)?
    @ObservationIgnored private let database: AccountDatabase
    @ObservationIgnored private let permit: SessionMutationPermit
    @ObservationIgnored private let service: ReminderService
    @ObservationIgnored private var observation: Task<Void, Never>?
    public init(database: AccountDatabase, permit: SessionMutationPermit, service: ReminderService) {
        self.database = database
        self.permit = permit
        self.service = service
    }
    public var active: Bool { permission?.remindersActive(settings) == true }
    public func start() async {
        if let rows = try? await SettingsRepository(database: database).settings() {
            settings = rows.first { $0.section == "reminders" }.flatMap { try? $0.value.decode(ReminderSettings.self) }
        }
        await refreshPermission()
        guard !Task.isCancelled, observation == nil else { return }
        observation = Task { [weak self, database] in
            do {
                for try await rows in try await SettingsRepository(database: database).values() {
                    guard !Task.isCancelled else { return }
                    self?.settings = rows.first { $0.section == "reminders" }.flatMap {
                        try? $0.value.decode(ReminderSettings.self)
                    }
                }
            } catch { self?.failure = error }
        }
    }
    public func refreshPermission() async {
        let previous = permission
        permission = await service.center.permission()
        if permission == .granted, previous == .blocked || previous == .undetermined {
            do { try await write(enabled: true) } catch { failure = error }
        }
    }
    public func requestPermission() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            permission = try await service.center.requestPermission()
            if permission == .granted { try await write(enabled: true) }
            await service.reschedule()
        } catch { failure = error }
    }
    public func setEnabled(_ enabled: Bool) async {
        guard !busy, permission == .granted else { return }
        busy = true
        defer { busy = false }
        do { try await write(enabled: enabled) } catch { failure = error }
    }
    public func setLead(_ minutes: Int) async {
        guard !busy, [15, 30, 60].contains(minutes), settings != nil else { return }
        busy = true
        defer { busy = false }
        do {
            try await OutboxRepository(database: database).enqueue(
                .settings(section: .reminders, patch: JSONObject(["lead_min": .number(Decimal(minutes))])),
                permit: permit)
            await service.reschedule()
        } catch { failure = error }
    }
    private func write(enabled: Bool) async throws {
        guard settings != nil else { return }
        try await OutboxRepository(database: database).enqueue(
            .settings(
                section: .reminders,
                patch: JSONObject([
                    "light": .bool(enabled), "avoid": .bool(enabled), "caffeine": .bool(enabled),
                    "winddown": .bool(enabled),
                ])), permit: permit)
        failure = nil
        await service.reschedule()
    }
    public func stop() {
        observation?.cancel()
        observation = nil
    }
    deinit { observation?.cancel() }
}
