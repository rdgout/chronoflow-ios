import Foundation

public enum MemberWizardDestination: Hashable, Sendable {
    case outbound, returnChoice, returnRoute, returnFlight, sleep, checking
    case question(Int)
    case excluded, continuation, fineTune, ready, calculating

    var step: MemberWizardStep {
        switch self {
        case .outbound: .outbound
        case .returnChoice: .returnChoice
        case .returnRoute: .returnRoute
        case .returnFlight: .returnFlight
        case .sleep: .sleep
        case .checking: .checking
        case .question: .question
        case .excluded: .excluded
        case .continuation: .continuation
        case .fineTune: .fineTune
        case .ready: .ready
        case .calculating: .calculating
        }
    }
}

extension MemberWizardModel {
    public var navigationPath: [MemberWizardDestination] {
        let step = draft.state.step
        if step == .whereTo { return [] }
        if step == .outbound { return [.outbound] }
        var result: [MemberWizardDestination] = [.outbound]
        if mode == .member { result.append(.returnChoice) }
        if step == .returnChoice { return result }
        if mode == .member, draft.form.end.kind == "return_legs" {
            result.append(.returnRoute)
            if step == .returnRoute { return result }
            result.append(.returnFlight)
        }
        if step == .returnFlight { return result }
        if mode == .guest || draft.state.sleepNeeded || draft.state.lastInputStep == .sleep || step == .sleep {
            result.append(.sleep)
        }
        switch step {
        case .checking: result.append(.checking)
        case .question:
            for index in 0...(draft.state.questionIndex ?? 0) { result.append(.question(index)) }
        case .excluded: result.append(.excluded)
        case .continuation, .fineTune: result.append(.fineTune)
        case .ready, .calculating:
            if !optionalPrompts.isEmpty { result.append(.fineTune) }
            result.append(.ready)
            if step == .calculating { result.append(.calculating) }
        default: break
        }
        return result
    }

    public func popNavigation(to path: [MemberWizardDestination], from presented: [MemberWizardDestination]) {
        // SwiftUI can finish writing an older stack after a review has already changed the step.
        guard draft.state.step != .calculating, presented == navigationPath, path.count < presented.count,
            presented.starts(with: path)
        else { return }
        if case .question(let index) = path.last {
            navigateToQuestion(index)
        } else {
            go(path.last?.step ?? .whereTo)
        }
    }
}
