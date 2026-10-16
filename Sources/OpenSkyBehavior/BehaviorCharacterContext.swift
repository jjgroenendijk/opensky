// What a graph needs to know about the character it runs on, and what it hands
// back beyond the pose. The engine sets the context before each update; a test
// leaves it at the defaults, where the character stands at the origin on flat ground.

import Foundation
import simd

/// Answers where the ground is under a point, in model space.
nonisolated public protocol BehaviorGroundProbe {
    /// The ground height at `point`'s x and y, searched from `up` above to `down`
    /// below it. Nil when nothing is there.
    func groundHeight(at point: SIMD3<Float>, up: Float, down: Float) -> Float?

    /// How far along the segment from `start` to `end` a sphere of `radius` first
    /// touches geometry, as a fraction from 0 to 1. Nil when it touches nothing.
    func firstHit(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float) -> Float?
}

/// The character's placement in the world, and its ground.
nonisolated public struct BehaviorCharacterContext {
    public var worldPosition: SIMD3<Float>
    public var worldRotation: simd_quatf
    public var ground: (any BehaviorGroundProbe)?

    public init(
        worldPosition: SIMD3<Float> = SIMD3(),
        worldRotation: simd_quatf = BehaviorPoseMath.identityRotation,
        ground: (any BehaviorGroundProbe)? = nil
    ) {
        self.worldPosition = worldPosition
        self.worldRotation = worldRotation
        self.ground = ground
    }

    public func modelPoint(fromWorld point: SIMD3<Float>) -> SIMD3<Float> {
        worldRotation.inverse.act(point - worldPosition)
    }

    public func worldPoint(fromModel point: SIMD3<Float>) -> SIMD3<Float> {
        worldRotation.act(point) + worldPosition
    }
}

/// The physics hand-offs the last update's modifiers asked for. Nil fields mean
/// no running modifier asked.
nonisolated public struct BehaviorPhysicsRequests: Equatable, Sendable {
    /// `hkbKeyframeBonesModifier`: bones the ragdoll should follow the animation for.
    public var keyframedBones: [Int]?
    /// `hkbGetUpModifier`: blend from the ragdoll back to animation over
    /// `duration`, aligning with `groundNormal` over `alignDuration`.
    public var getUp: BehaviorGetUpRequest?
    /// `hkbFootIkControlsModifier`: the foot IK gains, by Havok member name.
    public var footIkGains: [String: Float]?

    public init() {}
}

nonisolated public struct BehaviorGetUpRequest: Equatable, Sendable {
    public let groundNormal: SIMD3<Float>
    public let duration: Float
    public let alignDuration: Float
    public let rootBoneIndex: Int
}
