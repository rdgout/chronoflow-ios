import Foundation
import Testing

@testable import DesignSystem

struct AuthBoardContrastTests {
    @Test func guestFooterExceptionRequiresTheRecordedBoardColorsAndRatios() {
        #expect(Typography.authLabel.face == .figtree500)
        #expect(Typography.authLabel.size == 14)
        #expect(Typography.authLabel.lineHeight == 20)
        let recorded: [[[Double]]] = [
            [
                [0.0746269467, 0.0960047157, 0.1879246112, 1],
                [0.9554061387, 0.9691773029, 0.9866671639, 0.9],
                [0.1284753585, 0.1565420056, 0.3411446479, 1],
                [0.2951486928, 0.2590667942, 0.4835849939, 1],
                [0.8732523385, 0.6048251546, 0.4334483478, 1],
            ],
            [
                [0.9039299719, 0.9230007624, 0.9590599670, 1],
                [0.0426907083, 0.0547508757, 0.1152662036, 0.9],
                [0.0259695822, 0.0360074373, 0.1041462153, 1],
                [0.1281055407, 0.1029479048, 0.2428664457, 1],
                [0.6228083277, 0.3603616514, 0.2227518339, 1],
            ],
        ]
        let boardRatios = [(14.92601267, 2.31277682), (15.09530718, 2.94496265)]
        let ranges = [
            (13.46347008, 15.08823120, 2.00036967, 10.74339349),
            (14.94733150, 16.12979157, 1.00008668, 3.49967432),
        ]
        for (index, appearance) in TokenAppearance.allCases.enumerated() {
            for (offset, token) in [ColorToken.skyCopy, .skyCopyBackground, .skyTop, .skyMid, .skyHorizon].enumerated()
            {
                let color = token.components(for: appearance)
                #expect(
                    [color.red, color.green, color.blue, color.alpha] == recorded[index][offset],
                    "Re-review board contrast accepted, OQ 33 (user 2026-11-06), when board colors change")
            }
            let ramp = appearance == .light ? SkyRamp.light : SkyRamp.dark
            #expect(ramp.contains { $0.location == (appearance == .light ? 0.55 : 0.6) })
            let text = ColorToken.skyCopy.components(for: appearance)
            let pill = ColorToken.skyCopyBackground.components(for: appearance)
            func ratios(at location: Double) -> (text: Double, boundary: Double) {
                let hi = ramp.firstIndex { $0.location >= location }!
                let lo = max(0, hi - 1)
                let fraction = hi == lo ? 0 : (location - ramp[lo].location) / (ramp[hi].location - ramp[lo].location)
                func channels(_ color: TokenRGBA) -> [Double] { [color.red, color.green, color.blue] }
                let sky = zip(channels(ramp[lo].color), channels(ramp[hi].color)).map { $0 + ($1 - $0) * fraction }
                let surface = zip(channels(pill), sky).map { $0 * pill.alpha + $1 * (1 - pill.alpha) }
                return (contrast(channels(text), surface), contrast(surface, sky))
            }
            // The board footer's centre is 24 + 48/2 points above the bottom of its 812-point sky.
            let board = ratios(at: 764.0 / 812)
            #expect(abs(board.text - boardRatios[index].0) < 0.0001)
            #expect(abs(board.boundary - boardRatios[index].1) < 0.0001)
            let samples = (0...1000).map { ratios(at: Double($0) / 1000) }
            let measured = [
                samples.map(\.text).min()!, samples.map(\.text).max()!, samples.map(\.boundary).min()!,
                samples.map(\.boundary).max()!,
            ]
            let expected = ranges[index]
            #expect(
                zip(measured, [expected.0, expected.1, expected.2, expected.3]).allSatisfy { abs($0 - $1) < 0.0001 })
            #expect(samples.allSatisfy { $0.text >= 4.5 })
            #expect(board.boundary < 3)
            print(
                "Auth guest board contrast \(appearance): text/pill \(board.text):1; pill/sky \(board.boundary):1; full sky ranges \(measured)"
            )
        }
    }

    private func contrast(_ first: [Double], _ second: [Double]) -> Double {
        func luminance(_ p3: [Double]) -> Double {
            let linear = p3.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            let srgb = [
                1.2249401763 * linear[0] - 0.2249401763 * linear[1],
                -0.0420569547 * linear[0] + 1.0420569547 * linear[1],
                -0.0196375546 * linear[0] - 0.0786360456 * linear[1] + 1.0982736001 * linear[2],
            ]
            return zip(srgb, [0.2126, 0.7152, 0.0722]).reduce(0) { $0 + min(1, max(0, $1.0)) * $1.1 }
        }
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
