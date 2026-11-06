import CoreGraphics

@MainActor
public final class MoonAnchorStore {
    public private(set) var frame: CGRect?
    public var onChange: (@MainActor (CGRect) -> Void)?

    public init() {}

    public func update(_ frame: CGRect) {
        guard !frame.isNull, !frame.isInfinite, frame.width > 0, frame.height > 0,
            [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite), self.frame != frame
        else { return }
        self.frame = frame
        onChange?(frame)
    }
}
