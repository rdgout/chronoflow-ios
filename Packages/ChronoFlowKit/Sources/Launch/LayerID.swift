import CoreGraphics
import Foundation

nonisolated public enum LayerID: String, CaseIterable, Sendable {
    case container, sky, halo, sun, band, path, plane, moon, wordmark, status, statusDot
}

nonisolated public enum TrackValue: Sendable, Equatable {
    case scalar(Double)
    case point(CGPoint)

    func interpolated(to other: Self, progress: Double) -> Self {
        switch (self, other) {
        case (.scalar(let start), .scalar(let end)):
            .scalar(start + (end - start) * progress)
        case (.point(let start), .point(let end)):
            .point(CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress))
        default:
            preconditionFailure("Track values must have the same type")
        }
    }
}

nonisolated public struct LayerValues: Sendable, Equatable {
    public internal(set) var properties: [String: TrackValue] = [:]
    public internal(set) var replicaOpacities: [Double] = []

    public subscript(keyPath: String) -> TrackValue? { properties[keyPath] }
}
