import Foundation

nonisolated enum SoftwareKeyboardVisibility {
    static func isVisible(_ keyboard: CGRect, in window: CGRect) -> Bool {
        guard [keyboard, window].allSatisfy({ !$0.isEmpty && !$0.isInfinite && !$0.isNull }) else { return false }
        let visible = keyboard.intersection(window)
        // Hardware-keyboard accessory strips and clipped slivers must not count as a software keyboard.
        return visible.width >= 100 && visible.height >= 100
    }
}

nonisolated struct FrameStability {
    private var previous: [CGRect]?
    private var equalSamples = 0
    let requiredSamples: Int

    init(requiredSamples: Int = 3) {
        precondition(requiredSamples >= 2)
        self.requiredSamples = requiredSamples
    }

    mutating func observe(_ frames: [CGRect]?) -> Bool {
        guard let frames, !frames.isEmpty,
            frames.allSatisfy({ !$0.isEmpty && !$0.isInfinite && !$0.isNull })
        else {
            equalSamples = 0
            previous = nil
            return false
        }
        equalSamples = frames == previous ? equalSamples + 1 : 1
        previous = frames
        return equalSamples >= requiredSamples
    }
}
