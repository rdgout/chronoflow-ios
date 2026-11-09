import AppCore

public func legendDescription(_ type: BlockType) -> String {
    switch type {
    case .sleep: "Your main sleep window."
    case .nap: "A planned nap."
    case .rest: "Time set aside for rest."
    case .seekLight: "Follow the light source shown in your plan."
    case .lightOK: "No special action needed."
    case .lightNeutral: "Ordinary indoor or cabin light is fine."
    case .avoidLight: "Follow your plan's guidance to keep light low."
    case .caffeineServing: "A timed serving in your plan."
    case .caffeineRoutine: "Your daily caffeine guidance."
    case .caffeineOK: "A time window for caffeine in your plan."
    case .noCaffeine: "A time to avoid caffeine in your plan."
    case .flight: "Your flight."
    case .layover: "Time between flights."
    case .transfer: "The trip to or from the airport around your flight."
    case .movementBreak: "Time to get up and move."
    case .zoneChange: "A change in local time during your trip."
    case .note: "Extra guidance in your plan."
    default: "Extra guidance in your plan."
    }
}

public func priorityDescription(_ priority: Priority) -> String {
    switch priority {
    case .core: "Your plan depends on this step."
    case .recommended: "Helps your clock shift as planned."
    case .optional: "Nice if you can."
    default: "Good to know, nothing to do."
    }
}
