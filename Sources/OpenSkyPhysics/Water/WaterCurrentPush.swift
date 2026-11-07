// How a current moves an actor standing or swimming in it. Rules from the game's
// behaviour; see docs/engine/water-physics.md#actors-in-a-current.

import OpenSkyFormatsMesh
import simd

/// What a race decides about current pushes.
nonisolated public struct WaterPushRace: Equatable, Sendable {
    /// `fWaterKnockdownVelocity` times the race size factor, Havok units per second.
    public var strongCurrent: Float
    /// A race that swims and neither walks nor flies is never pushed.
    public var isSwimOnly: Bool

    public init(strongCurrent: Float, isSwimOnly: Bool = false) {
        self.strongCurrent = strongCurrent
        self.isSwimOnly = isSwimOnly
    }

    /// `fWaterKnockdownVelocity` 5 times the normal size factor 0.75.
    public static let normal = WaterPushRace(strongCurrent: 5 * 0.75)
}

/// One actor's side of a current push.
nonisolated public struct WaterPushActor: Equatable, Sendable {
    /// The actor's own horizontal velocity this step, game units per second.
    public var ownVelocity: SIMD2<Float>
    /// Positive up.
    public var verticalVelocity: Float
    public var isSwimming: Bool
    /// The swim speed while swimming, else the run speed.
    public var maximumSpeed: Float
    public var race: WaterPushRace

    public init(
        ownVelocity: SIMD2<Float>, verticalVelocity: Float, isSwimming: Bool,
        maximumSpeed: Float, race: WaterPushRace = .normal
    ) {
        self.ownVelocity = ownVelocity
        self.verticalVelocity = verticalVelocity
        self.isSwimming = isSwimming
        self.maximumSpeed = maximumSpeed
        self.race = race
    }
}

nonisolated public enum WaterCurrentPush {
    /// Falling faster than this, game units per second, lets any current push.
    public static let fallingSpeed: Float = 700

    /// The velocity a current adds to an actor, game units per second.
    public static func velocity(
        current: SIMD3<Float>, actor: WaterPushActor
    ) -> SIMD3<Float> {
        guard !actor.race.isSwimOnly, current != .zero else { return .zero }
        let flat = SIMD2(current.x, current.y)
        let isStrong = simd_length(flat) / NIFCollisionModel.havokToEngineScale
            > actor.race.strongCurrent
        if isStrong {
            return current
        }
        guard actor.isSwimming || actor.verticalVelocity < -fallingSpeed else { return .zero }
        let total = actor.ownVelocity + flat
        let length = simd_length(total)
        guard length > actor.maximumSpeed else { return current }
        let allowed = length > 0 ? total * (actor.maximumSpeed / length) : .zero
        let added = allowed - actor.ownVelocity
        // The cap only takes away what the current added.
        let push = simd_dot(added, flat) > 0 ? added : .zero
        return SIMD3(push.x, push.y, current.z)
    }
}
