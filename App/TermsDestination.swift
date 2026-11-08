import AppCore
import DesignSystem
import LocalStore
import Settings
import SwiftUI

struct TermsDestination: View {
    let native: NativeSessionController
    @State private var model: TermsUpdateModel?
    @State private var signOut: SettingsHomeModel?

    var body: some View {
        ZStack {
            ColorToken.background.color.ignoresSafeArea()
            if let model, let signOut { TermsUpdateView(model: model, signOut: signOut) }
        }.task {
            while !Task.isCancelled {
                if let snapshot = await native.controller.activeSession(),
                    let database = await native.accounts.activeDatabase(),
                    await database.accountID?.rawValue == snapshot.session.accountId,
                    let permit = await native.controller.mutationPermit(for: snapshot),
                    await native.controller.activeSession() == snapshot, !Task.isCancelled
                {
                    #if DEBUG
                        do {
                            try await seedTermsPending(database: database, permit: permit)
                        } catch { return }
                    #endif
                    let terms = TermsUpdateModel { version in
                        guard await native.controller.activeSession() == snapshot else { throw CancellationError() }
                        try await OutboxRepository(database: database).enqueue(
                            .policies(version: version), permit: permit)
                    }
                    let settings = SettingsHomeModel(
                        database: database, controller: native.controller, session: snapshot, sync: native.sync)
                    model = terms
                    signOut = settings
                    settings.start()
                    defer { settings.stop() }
                    do {
                        for try await values in try await SettingsRepository(database: database).values() {
                            guard await native.controller.activeSession() == snapshot, !Task.isCancelled else { return }
                            terms.update(
                                policies: try values.first { $0.section == "policies" }?.value.decode(
                                    AccountPolicies.self))
                        }
                    } catch {}
                    model = nil
                    signOut = nil
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }
}
