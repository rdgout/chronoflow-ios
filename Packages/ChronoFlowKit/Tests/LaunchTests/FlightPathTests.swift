import CoreGraphics
import Foundation
import QuartzCore
import Testing

@testable import Launch

struct FlightPathTests {
    @Test func boardGeometryAndArcLength() {
        let flight = FlightPath(size: CGSize(width: 390, height: 844))
        #expect(abs(flight.length - 505.8) < 0.2)
        #expect(flight.start == CGPoint(x: -10, y: 640))
        #expect(flight.control1 == CGPoint(x: 90, y: 470))
        #expect(flight.control2 == CGPoint(x: 300, y: 470))
        #expect(flight.end == CGPoint(x: 400, y: 640))
        let apex = flight.point(atFraction: 0.5)
        #expect(abs(apex.x - 195) < 1e-8)
        #expect(abs(apex.y - 512.5) < 1e-8)
        #expect(flight.point(atFraction: -1) == flight.start)
        #expect(flight.point(atFraction: 2) == flight.end)
    }

    @Test func bottomAnchoringAndWidthScaling() {
        for size in [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874), CGSize(width: 590, height: 900)]
        {
            let flight = FlightPath(size: size)
            #expect(flight.start.y == size.height - 204)
            #expect(flight.control1.y == size.height - 374)
            #expect(flight.control2.y == size.height - 374)
            #expect(flight.end.x == size.width + 10)
            #expect(flight.control1.x == 90 * size.width / 390)
            #expect(flight.control2.x == 300 * size.width / 390)
            #expect(abs(flight.point(atFraction: 0.5).y - (size.height - 331.5)) < 1e-8)
        }
    }

    @Test func fractionCurveAnd128PositionKeys() {
        #expect(FlightPath.fraction(at: .milliseconds(0)) == 0)
        #expect(FlightPath.fraction(at: .milliseconds(500)) == 0)
        #expect(abs(FlightPath.fraction(at: .milliseconds(560)) - 0.03) < 1e-12)
        #expect(abs(FlightPath.fraction(at: .milliseconds(980)) - 0.515) < 1e-12)
        #expect(FlightPath.fraction(at: .milliseconds(1400)) == 1)
        #expect(FlightPath.fraction(at: .seconds(9)) == 1)
        let flight = FlightPath(size: CGSize(width: 390, height: 844))
        let times = flight.positionKeyTimes
        #expect(times.count == 128)
        #expect(flight.positionValues.count == 128)
        #expect(times.first == 0.5)
        #expect(times.last == 1.4)
        #expect(times.contains(0.56))
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
        var vertices: [CGPoint] = []
        flight.path.applyWithBlock { element in
            #expect(element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint)
            vertices.append(element.pointee.points[0])
        }
        #expect(vertices == flight.positionValues)
        for (time, point) in zip(times, flight.positionValues) {
            let expected = flight.point(atFraction: FlightPath.fraction(at: .seconds(time)))
            #expect(hypot(point.x - expected.x, point.y - expected.y) < 1e-8)
        }
    }

    @Test func lookupAgreesWithIndependentDenseIntegrationEvery10Milliseconds() {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 375, height: 667), CGSize(width: 590, height: 900)]
        {
            let flight = FlightPath(size: size)
            let reference = denseReference(flight)
            #expect(abs(flight.length - reference.last!.length) < 0.001)
            for milliseconds in stride(from: 500, through: 1400, by: 10) {
                let fraction = FlightPath.fraction(at: .milliseconds(milliseconds))
                let point = flight.point(atFraction: fraction)
                let distance = fraction * reference.last!.length
                let nearest = reference.min { abs($0.length - distance) < abs($1.length - distance) }!
                #expect(hypot(point.x - nearest.point.x, point.y - nearest.point.y) < 0.04)
            }
        }
    }

    @Test func shapeLayerStrokeTipMatchesArcLengthEvery10Milliseconds() throws {
        let flight = FlightPath(size: CGSize(width: 390, height: 844))
        let layer = CAShapeLayer()
        layer.frame = CGRect(origin: .zero, size: flight.size)
        layer.path = flight.path
        layer.fillColor = nil
        layer.strokeColor = CGColor(gray: 1, alpha: 1)
        layer.lineWidth = 1.5
        layer.lineCap = .butt
        let scale = 3
        let width = 390 * scale
        let height = 844 * scale
        var pixels = [UInt8](repeating: 0, count: width * height)
        for milliseconds in stride(from: 560, through: 1380, by: 10) {
            let fraction = FlightPath.fraction(at: .milliseconds(milliseconds))
            layer.strokeEnd = fraction
            try pixels.withUnsafeMutableBytes { bytes in
                let context = try #require(
                    CGContext(
                        data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue))
                context.clear(CGRect(x: 0, y: 0, width: width, height: height))
                context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                layer.render(in: context)
            }
            for (offset, shouldBeDrawn) in [(-1.0, true), (1.0, false)] {
                let point = flight.point(atFraction: fraction + offset / flight.length)
                let x = Int(point.x * Double(scale))
                let y = Int(point.y * Double(scale))
                guard x >= 0 && x < width && y >= 0 && y < height else { continue }
                #expect(
                    (pixels[(height - 1 - y) * width + x] > 128) == shouldBeDrawn,
                    "tip at \(milliseconds) ms, offset \(offset)")
            }
        }
    }

    private func denseReference(_ flight: FlightPath) -> [(point: CGPoint, length: Double)] {
        var result = [(flight.start, 0.0)]
        for index in 1...32768 {
            let t = Double(index) / 32768
            let u = 1 - t
            let point = CGPoint(
                x: u * u * u * flight.start.x + 3 * u * u * t * flight.control1.x
                    + 3 * u * t * t * flight.control2.x + t * t * t * flight.end.x,
                y: u * u * u * flight.start.y + 3 * u * u * t * flight.control1.y
                    + 3 * u * t * t * flight.control2.y + t * t * t * flight.end.y)
            let previous = result.last!
            result.append((point, previous.1 + hypot(point.x - previous.0.x, point.y - previous.0.y)))
        }
        return result
    }
}
