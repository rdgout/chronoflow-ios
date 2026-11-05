import Foundation

public struct RGB: Equatable, Sendable {
    public let values: [Double]

    public var hex: String {
        "#" + values.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }

    public func mixed(with other: RGB, fraction: Double) -> RGB {
        RGB(values: zip(values, other.values).map { $0 + ($1 - $0) * fraction })
    }
}

public struct OKLab: Sendable {
    public let lightness: Double
    public let a: Double
    public let b: Double
    public let alpha: Double

    public init(css: String) throws {
        let parts = css.replacingOccurrences(of: "oklch(", with: "").replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "/", with: " ").split(separator: " ").compactMap { Double($0) }
        guard parts.count == 3 || parts.count == 4 else { throw GenerationError.invalid("Invalid OKLCH: \(css)") }
        lightness = parts[0]
        a = parts[1] * cos(parts[2] * .pi / 180)
        b = parts[1] * sin(parts[2] * .pi / 180)
        alpha = parts.count == 4 ? parts[3] : 1
    }

    public init(lightness: Double, a: Double, b: Double, alpha: Double = 1) {
        self.lightness = lightness
        self.a = a
        self.b = b
        self.alpha = alpha
    }

    public func mixed(with other: OKLab, fraction: Double) -> OKLab {
        OKLab(
            lightness: lightness + (other.lightness - lightness) * fraction,
            a: a + (other.a - a) * fraction, b: b + (other.b - b) * fraction,
            alpha: alpha + (other.alpha - alpha) * fraction)
    }

    public func rgb(p3: Bool) -> RGB {
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        let linear =
            p3
            ? [
                0.8224619687 * r + 0.1775380313 * g,
                0.0331941989 * r + 0.9668058011 * g,
                0.0170826307 * r + 0.0723974407 * g + 0.9105199286 * b,
            ] : [r, g, b]
        return RGB(
            values: linear.map {
                let clipped = min(1, max(0, $0))
                return clipped <= 0.0031308 ? 12.92 * clipped : 1.055 * pow(clipped, 1 / 2.4) - 0.055
            })
    }
}

public enum GenerationError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self {
        case .invalid(let message): message
        }
    }
}

public struct RampStop: Sendable {
    public let location: Double
    public let color: RGB
}

public func skyRamp(top: OKLab, mid: OKLab, horizon: OKLab, midStop: Double) -> [RampStop] {
    func segment(_ a: OKLab, _ b: OKLab, _ start: Double, _ end: Double, _ divisions: Int) -> [RampStop] {
        (0...divisions).map { i in
            let f = Double(i) / Double(divisions)
            return RampStop(location: start + (end - start) * f, color: a.mixed(with: b, fraction: f).rgb(p3: true))
        }
    }
    var divisions = 1
    while true {
        let stops = segment(top, mid, 0, midStop, divisions).dropLast() + segment(mid, horizon, midStop, 1, divisions)
        let valid = (0...1000).allSatisfy { i in
            let x = Double(i) / 1000
            let trueColor =
                x <= midStop
                ? top.mixed(with: mid, fraction: x / midStop).rgb(p3: true)
                : mid.mixed(with: horizon, fraction: (x - midStop) / (1 - midStop)).rgb(p3: true)
            let hi = stops.firstIndex { $0.location >= x } ?? stops.count - 1
            let lo = max(0, hi - 1)
            let f = hi == lo ? 0 : (x - stops[lo].location) / (stops[hi].location - stops[lo].location)
            let approximation = stops[lo].color.mixed(with: stops[hi].color, fraction: f)
            return zip(approximation.values, trueColor.values).allSatisfy { abs($0 - $1) <= 0.25 / 255.0 }
        }
        if valid { return Array(stops) }
        divisions *= 2
    }
}
