// An actor in a current: the push the water adds to one step
// (docs/engine/water-physics.md#actors-in-a-current).

import OpenSkyPhysics
import simd

nonisolated extension LocomotionStepPlan {
    /// Adds the current's push to this plan, when the feet are under the surface.
    public mutating func applyCurrent(
        _ water: WaterReading?, state: LocomotionStepState,
        configuration: PlayerMovementConfiguration, race: WaterPushRace
    ) {
        guard let water, water.surface > state.feetPosition.z, state.dt > 0 else { return }
        self.water = water
        let swimming = isSwimming
        let push = WaterCurrentPush.velocity(
            current: water.current,
            actor: WaterPushActor(
                ownVelocity: horizontalDisplacement / state.dt,
                verticalVelocity: state.verticalVelocity, isSwimming: swimming,
                maximumSpeed: swimming
                    ? configuration.swimSpeed.value : configuration.runSpeed.value,
                race: race
            )
        )
        waterPush = push
        horizontalDisplacement += SIMD2(push.x, push.y) * state.dt
        if swimming {
            swimVerticalVelocity += push.z
        }
    }
}
