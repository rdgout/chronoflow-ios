import AppCore
import DesignSystem
import LocalStore
import PlanUI
import SwiftUI

struct WalkthroughDestination: View {
    let native: NativeSessionController
    @State private var model: WalkthroughModel?

    var body: some View {
        ZStack {
            ColorToken.background.color.ignoresSafeArea()
            if let model { WalkthroughView(model: model) }
        }.task {
            while model == nil, !Task.isCancelled {
                if let snapshot = await native.controller.activeSession(),
                    let database = await native.accounts.activeDatabase(),
                    await database.accountID?.rawValue == snapshot.session.accountId,
                    let permit = await native.controller.mutationPermit(for: snapshot),
                    await native.controller.activeSession() == snapshot, !Task.isCancelled
                {
                    model = WalkthroughModel {
                        guard await native.controller.activeSession() == snapshot else { throw CancellationError() }
                        try await OutboxRepository(database: database).enqueue(.walkthrough, permit: permit)
                    }
                } else {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
            }
        }
    }
}
