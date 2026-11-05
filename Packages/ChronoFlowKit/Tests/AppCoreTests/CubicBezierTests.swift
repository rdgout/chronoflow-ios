import Foundation
import Testing

@testable import AppCore

struct CubicBezierTests {
    @Test func cssReferenceValues() {
        let inputs = [0.1, 0.25, 0.5, 0.75, 0.9]
        let references: [(CubicBezier, [Double])] = [
            (.easeOut, [0.1605721542, 0.3781381308, 0.6846431874, 0.9065353493, 0.9829733903]),
            (.easeInOut, [0.0197224535, 0.1291619310, 0.5, 0.8708380690, 0.9802775465]),
            (.intro, [0.3966935490, 0.7672843007, 0.9460794615, 0.9911081873, 0.9988302593]),
            (.linear, inputs),
        ]
        for (curve, values) in references {
            for (input, expected) in zip(inputs, values) {
                #expect(abs(curve.value(at: input) - expected) < 1e-4)
            }
            #expect(curve.value(at: 0) == 0)
            #expect(curve.value(at: 1) == 1)
            #expect(curve.value(at: -1) == 0)
            #expect(curve.value(at: 2) == 1)
        }
    }

    @Test func flatDerivativesAndOvershootingY() {
        let cubeRoot = CubicBezier(0, 1.0 / 3, 0, 2.0 / 3)
        for input in [1e-9, 0.001, 0.125, 0.9] {
            #expect(abs(cubeRoot.value(at: input) - pow(input, 1.0 / 3)) < 1e-5)
        }
        let flatMiddle = CubicBezier(1, 0, 0, 1)
        for input in [0.499999, 0.5, 0.500001] {
            let t = 0.5 + cbrt((input - 0.5) / 4)
            #expect(abs(flatMiddle.value(at: input) - (3 * t * t - 2 * t * t * t)) < 1e-5)
        }
        #expect(CubicBezier(0.3, -1, 0.7, 2).value(at: 0.1) < 0)
        #expect(CubicBezier(0.3, -1, 0.7, 2).value(at: 0.9) > 1)
    }

    @Test func presetControlsAndMonotonicity() {
        #expect(CubicBezier.easeOut == CubicBezier(0, 0, 0.58, 1))
        #expect(CubicBezier.easeInOut == CubicBezier(0.42, 0, 0.58, 1))
        #expect(CubicBezier.intro == CubicBezier(0.2, 0.8, 0.2, 1))
        #expect(CubicBezier.linear == CubicBezier(0, 0, 1, 1))
        for curve in [CubicBezier.easeOut, .easeInOut, .intro, .linear] {
            let values = (0...1000).map { curve.value(at: Double($0) / 1000) }
            #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        }
    }
}
