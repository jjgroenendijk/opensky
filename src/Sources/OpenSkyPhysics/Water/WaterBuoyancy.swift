// How a loose body floats and drifts in water. Rules from the game's behaviour;
// see docs/engine/water-physics.md#floating-bodies.

import Foundation
public import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import simd

nonisolated public enum WaterBuoyancy {
    /// Bodies farther than this from the player do not float.
    public static let playerRange: Float = 3213
    /// Bodies whose bottom is this far above the surface do not float.
    public static let surfaceGate: Float = 48
    static let havokScale = NIFCollisionModel.havokToEngineScale
    /// Below this horizontal speed the water does not slow a body.
    public static let horizontalDampingFloor: Float = 2 * havokScale

    /// How deep a box is in water: 0 with a quarter of it under the surface, 1 at 85%.
    public static func fill(bounds: ModelBounds, surface: Float) -> Float {
        let height = bounds.max.z - bounds.min.z
        guard height > 0 else { return surface >= bounds.min.z ? 1 : 0 }
        return (surface - (bounds.min.z + 0.25 * height)) / (0.6 * height)
    }

    /// The share of `buoyancy` that acts at `fill`: none up to half, then a ramp to full.
    public static func lift(fill: Float, buoyancy: Float) -> Float {
        if fill <= 0.5 {
            return 0
        }
        if fill < 0.75 {
            return buoyancy * (fill - 0.5) * 4
        }
        return buoyancy
    }

    /// One step of water on a body's velocity. `gravity` is the acceleration the
    /// body already took this step.
    public static func apply(
        to body: inout DynamicBody, immersion: WaterImmersion, gravity: SIMD3<Float>, dt: Float
    ) {
        let fill = immersion.fill, current = immersion.current
        let buoyancy = body.definition.buoyancy
        guard fill > 0 else { return }
        let up = -simd_normalize(gravity)
        body.linearVelocity += (-gravity + up * simd_length(gravity) * lift(
            fill: fill, buoyancy: buoyancy
        )) * dt
        body.linearVelocity.z *= exp(-4 * dt)
        let flat = SIMD2(body.linearVelocity.x, body.linearVelocity.y)
        if simd_length(flat) > horizontalDampingFloor {
            let damped = flat * exp(-2 * dt)
            body.linearVelocity.x = damped.x
            body.linearVelocity.y = damped.y
        }
        body.angularVelocity *= exp(-0.75 * dt)
        for axis in 0 ..< 3 where current[axis] != 0 {
            body.linearVelocity[axis] += (current[axis] - body.linearVelocity[axis]) * dt
        }
    }
}

/// How deep a body sits, and the current there in game units per second.
nonisolated public struct WaterImmersion: Equatable, Sendable {
    public var fill: Float
    public var current: SIMD3<Float>

    public init(fill: Float, current: SIMD3<Float>) {
        self.fill = fill
        self.current = current
    }
}

/// What the body solver needs to float bodies.
nonisolated public struct DynamicWaterWorld {
    public let sample: (SIMD3<Float>) -> WaterReading?
    /// Where the player is; bodies far from it do not float.
    public let player: SIMD3<Float>?

    public init(sample: @escaping (SIMD3<Float>) -> WaterReading?, player: SIMD3<Float>?) {
        self.sample = sample
        self.player = player
    }

    /// The fill and current a body is in, or nil when it does not float now.
    func immersion(of body: DynamicBody) -> WaterImmersion? {
        if let player, simd_distance(player, body.position) > WaterBuoyancy.playerRange {
            return nil
        }
        let bounds = body.worldBounds
        let probe = SIMD3(body.position.x, body.position.y, bounds.min.z)
        guard
            let water = sample(probe),
            bounds.min.z <= water.surface + WaterBuoyancy.surfaceGate
        else { return nil }
        let fill = WaterBuoyancy.fill(bounds: bounds, surface: water.surface)
        return fill > 0 ? WaterImmersion(fill: fill, current: water.current) : nil
    }
}
