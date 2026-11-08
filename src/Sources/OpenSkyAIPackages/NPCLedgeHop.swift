// The arc a walking actor follows across a navmesh ledge link: a jump up or a drop
// down. The actor leaves the walk controller for the hop and lands on the far side.
// OpenSky's own shape; see docs/engine/navigation.md.

import simd

nonisolated public struct NPCLedgeHop: Equatable, Sendable {
    /// Height above the higher end that the arc clears, world units.
    public static let clearance: Float = 32
    public static let minimumDuration: Float = 0.35
    public static let maximumDuration: Float = 1.2

    public let from: SIMD3<Float>
    public let landing: SIMD3<Float>
    public let duration: Float
    public private(set) var elapsed: Float = 0

    /// `speed` is the horizontal speed of the gait the actor jumps from.
    public init(from: SIMD3<Float>, landing: SIMD3<Float>, speed: Float) {
        self.from = from
        self.landing = landing
        let horizontal = simd_length(SIMD2(landing.x - from.x, landing.y - from.y))
        let time = speed > 0 ? horizontal / speed : Self.maximumDuration
        duration = min(max(time, Self.minimumDuration), Self.maximumDuration)
    }

    public var isFinished: Bool {
        elapsed >= duration
    }

    /// Feet on the arc: a straight line plus a parabola that peaks `clearance` above
    /// the higher end, so a jump up clears the lip and a drop starts with a small rise.
    public var feetPosition: SIMD3<Float> {
        let progress = min(max(elapsed / duration, 0), 1)
        let line = from + (landing - from) * progress
        let apex = max(landing.z, from.z) + Self.clearance
        let lift = apex - (from.z + landing.z) / 2
        return line + SIMD3(0, 0, 4 * lift * progress * (1 - progress))
    }

    public mutating func advance(by frameTime: Float) {
        elapsed = min(elapsed + max(frameTime, 0), duration)
    }
}
