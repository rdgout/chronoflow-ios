import CoreGraphics
import Foundation

nonisolated public struct FlightPath: Sendable, Equatable {
    public let size: CGSize
    public let start: CGPoint
    public let control1: CGPoint
    public let control2: CGPoint
    public let end: CGPoint
    public let length: Double
    private let distances: [Double]

    public init(size: CGSize) {
        precondition(size.width > 0 && size.height > 0 && size.width.isFinite && size.height.isFinite)
        self.size = size
        start = CGPoint(x: -10, y: size.height - 204)
        control1 = CGPoint(x: 90 * size.width / 390, y: size.height - 374)
        control2 = CGPoint(x: 300 * size.width / 390, y: size.height - 374)
        end = CGPoint(x: size.width + 10, y: size.height - 204)
        var table = [0.0]
        var previous = start
        for index in 1..<1024 {
            let point = Self.point(
                Double(index) / 1023, start: start, control1: control1, control2: control2, end: end)
            table.append(table[index - 1] + hypot(point.x - previous.x, point.y - previous.y))
            previous = point
        }
        distances = table
        length = table.last!
    }

    public var path: CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        // CAShapeLayer's cubic trimming drifts from arc length; line segments keep the stroke beside the plane.
        for point in positionValues.dropFirst() { path.addLine(to: point) }
        return path
    }

    public func point(atFraction fraction: Double) -> CGPoint {
        precondition(fraction.isFinite)
        let distance = min(1, max(0, fraction)) * length
        var lower = 0
        var upper = distances.count - 1
        while upper - lower > 1 {
            let middle = (lower + upper) / 2
            if distances[middle] < distance { lower = middle } else { upper = middle }
        }
        let progress = (distance - distances[lower]) / (distances[upper] - distances[lower])
        let parameter = (Double(lower) + progress) / Double(distances.count - 1)
        return Self.point(parameter, start: start, control1: control1, control2: control2, end: end)
    }

    public static func fraction(at time: Duration) -> Double {
        let seconds = time.timeInterval
        if seconds <= 0.5 { return 0 }
        if seconds < 0.56 { return (seconds - 0.5) / 0.06 * 0.03 }
        if seconds < 1.4 { return 0.03 + (seconds - 0.56) / 0.84 * 0.97 }
        return 1
    }

    public var positionKeyTimes: [Double] {
        positionFractions.map { fraction in
            fraction <= 0.03
                ? 0.5 + fraction / 0.03 * 0.06
                : 0.56 + (fraction - 0.03) / 0.97 * 0.84
        }
    }

    public var positionValues: [CGPoint] { positionFractions.map { point(atFraction: $0) } }

    private var positionFractions: [Double] {
        ((0..<127).map { Double($0) / 126 } + [0.03]).sorted()
    }

    private static func point(
        _ t: Double, start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint
    ) -> CGPoint {
        let a = (1 - t) * (1 - t) * (1 - t)
        let b = 3 * (1 - t) * (1 - t) * t
        let c = 3 * (1 - t) * t * t
        let d = t * t * t
        return CGPoint(
            x: a * start.x + b * control1.x + c * control2.x + d * end.x,
            y: a * start.y + b * control1.y + c * control2.y + d * end.y)
    }
}

extension Duration {
    nonisolated var timeInterval: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
