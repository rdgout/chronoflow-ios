#if canImport(UIKit)
    import SwiftUI

    struct TripPageStepSheet: View {
        let model: TripPageModel
        let selection: TripPageModel.StepSelection
        @State private var busy = false

        var body: some View {
            StepSheet(
                detail: model.plan.detail, blockID: selection.blockID, now: model.plan.now,
                formatter: selection.formatter, timeFormat: model.plan.timeFormat, busy: busy
            ) { status in
                guard !busy else { return }
                busy = true
                defer { busy = false }
                try? await model.plan.setCheck(blockID: selection.blockID, status: status)
            }
        }
    }
#endif
