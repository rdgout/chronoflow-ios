import AppCore
import LocalStore
import PlanUI
import SwiftUI

struct WalkthroughDestination: View {
    let native: NativeSessionController
    @State private var model: WalkthroughModel?

    var body: some View {
        Group {
            if let model { WalkthroughView(model: model) }
        }.task {
            guard model == nil, let snapshot = await native.controller.activeSession(),
                let database = await native.accounts.activeDatabase(),
                let permit = await native.controller.mutationPermit(for: snapshot),
                await native.controller.activeSession() == snapshot, !Task.isCancelled
            else { return }
            model = WalkthroughModel {
                guard await native.controller.activeSession() == snapshot else { throw CancellationError() }
                try await OutboxRepository(database: database).enqueue(.walkthrough, permit: permit)
            }
        }
    }
}
