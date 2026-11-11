import Foundation

public enum MemberWizardDestination: Hashable, Sendable {
    case outbound, returnChoice, returnFlight, sleep, checking
    case question(Int)
    case excluded, continuation

    var step: MemberWizardStep {
        switch self {
        case .outbound: .outbound
        case .returnChoice: .returnChoice
        case .returnFlight: .returnFlight
        case .sleep: .sleep
        case .checking: .checking
        case .question: .question
        case .excluded: .excluded
        case .continuation: .continuation
        }
    }
}

extension MemberWizardModel {
    public var navigationPath: [MemberWizardDestination] {
        let step = draft.state.step
        if step == .whereTo { return [] }
        if step == .outbound { return [.outbound] }
        var result: [MemberWizardDestination] = [.outbound, .returnChoice]
        if step == .returnChoice { return result }
        if draft.form.end.kind == "return_legs" { result.append(.returnFlight) }
        if step == .returnFlight { return result }
        if draft.state.sleepNeeded || draft.state.lastInputStep == .sleep || step == .sleep {
            result.append(.sleep)
        }
        switch step {
        case .checking: result.append(.checking)
        case .question:
            for index in 0...(draft.state.questionIndex ?? 0) { result.append(.question(index)) }
        case .excluded: result.append(.excluded)
        case .continuation: result.append(.continuation)
        default: break
        }
        return result
    }

    public func popNavigation(to path: [MemberWizardDestination], from presented: [MemberWizardDestination]) {
        // SwiftUI can finish writing an older stack after a review has already changed the step.
        guard presented == navigationPath, path.count < presented.count, presented.starts(with: path) else { return }
        if case .question(let index) = path.last {
            navigateToQuestion(index)
        } else {
            go(path.last?.step ?? .whereTo)
        }
    }
}
