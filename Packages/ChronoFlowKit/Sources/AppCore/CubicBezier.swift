import Foundation

public struct CubicBezier: Sendable, Equatable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        precondition((0...1).contains(x1) && (0...1).contains(x2) && y1.isFinite && y2.isFinite)
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    public static var easeOut: Self { Self(0, 0, 0.58, 1) }
    public static var easeInOut: Self { Self(0.42, 0, 0.58, 1) }
    public static var intro: Self { Self(0.2, 0.8, 0.2, 1) }
    public static var linear: Self { Self(0, 0, 1, 1) }

    public func value(at progress: Double) -> Double {
        precondition(progress.isFinite)
        if progress <= 0 { return 0 }
        if progress >= 1 { return 1 }
        if x1 == y1 && x2 == y2 { return progress }

        var lower = 0.0
        var upper = 1.0
        var parameter = progress
        for _ in 0..<8 {
            let error = coordinate(parameter, x1, x2) - progress
            if abs(error) < 1e-13 { return coordinate(parameter, y1, y2) }
            if error < 0 { lower = parameter } else { upper = parameter }
            let slope = derivative(parameter, x1, x2)
            guard abs(slope) > 1e-10 else { break }
            let next = parameter - error / slope
            guard next > lower && next < upper else { break }
            parameter = next
        }
        for _ in 0..<48 {
            parameter = (lower + upper) / 2
            let x = coordinate(parameter, x1, x2)
            if abs(x - progress) < 1e-13 { break }
            if x < progress { lower = parameter } else { upper = parameter }
        }
        return coordinate(parameter, y1, y2)
    }

    private func coordinate(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * t * a + 3 * inverse * t * t * b + t * t * t
    }

    private func derivative(_ t: Double, _ a: Double, _ b: Double) -> Double {
        3 * (1 - t) * (1 - t) * a + 6 * (1 - t) * t * (b - a) + 3 * t * t * (1 - b)
    }
}
