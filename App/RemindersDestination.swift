import DesignSystem
import Settings
import SwiftUI

struct RemindersDestination: View {
    let native: NativeSessionController?
    var firstTrip = false
    @Environment(\.dismiss) private var dismiss
    @State private var model: RemindersModel?

    var body: some View {
        ZStack {
            ColorToken.background.color.ignoresSafeArea()
            if let model {
                if firstTrip {
                    FirstTripRemindersSheet(model: model) { dismiss() }
                } else {
                    RemindersView(model: model)
                }
            }
        }.task {
            while !Task.isCancelled, model == nil {
                if let native, let snapshot = await native.controller.activeSession(),
                    let database = await native.accounts.activeDatabase(),
                    let permit = await native.controller.mutationPermit(for: snapshot),
                    await native.controller.activeSession() == snapshot
                {
                    model = RemindersModel(database: database, permit: permit, service: native.reminders)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
