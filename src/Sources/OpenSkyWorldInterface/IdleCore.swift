import Foundation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// Where a sandboxing actor takes idle markers: a cylinder round its package's place.
nonisolated public struct IdleSearchArea: Equatable, Sendable {
    public let center: SIMD3<Float>
    public let radius: Float
    /// Height below the centre, as a negative number, and above it.
    public let below: Float
    public let above: Float
    /// The next marker is at least this far from `previous`, the one the actor left.
    public let minimumStep: Float
    public var previous: SIMD3<Float>?
    public var allowsMarkers = true

    public init(
        center: SIMD3<Float>, radius: Float, height: ClosedRange<Float>, minimumStep: Float
    ) {
        self.center = center
        self.radius = radius
        below = height.lowerBound
        above = height.upperBound
        self.minimumStep = minimumStep
    }

    public func contains(_ point: SIMD3<Float>) -> Bool {
        let offset = point - center
        let tooClose = previous.map { simd_distance($0, point) < minimumStep } ?? false
        return simd_length(SIMD2(offset.x, offset.y)) <= radius
            && offset.z >= below && offset.z <= above && !tooClose
    }
}
