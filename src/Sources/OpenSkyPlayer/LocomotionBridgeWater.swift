// The player in water: the push a current adds to one step
// (docs/engine/water-physics.md#actors-in-a-current), and the swim rule
// (docs/engine/ground-and-water-contact.md#water).

public import OpenSkyPhysics
public import OpenSkyWorldInterface
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

nonisolated extension LocomotionBridge {
    /// The water surface to swim against, or nil to stay on land (`SwimRule.swims`).
    func swimSurface(
        _ water: WaterReading?, at state: LocomotionStepState, wasSwimming: Bool
    ) -> Float? {
        guard let surface = water?.surface, surface.isFinite else { return nil }
        let contact = SwimContact(
            submersion: SwimRule.submersion(
                surface: surface, feetHeight: state.feetPosition.z, bodyHeight: state.bodyHeight
            ),
            wasSwimming: wasSwimming,
            hasGroundBelow: state.isGrounded,
            isRising: state.verticalVelocity > 0
        )
        return SwimRule.swims(contact) ? surface : nil
    }

    /// The takeoff of a jump out of the water, twice as high as on land, or nil when the
    /// float point is too deep under the surface.
    func swimJumpImpulse(state: LocomotionStepState, surface: Float) -> Float? {
        let floatPoint = SwimRule.floatPointHeight(
            feetHeight: state.feetPosition.z, bodyHeight: state.bodyHeight,
            floatLevel: swimFloatLevel
        )
        guard SwimRule.canJumpOut(surface: surface, floatPointHeight: floatPoint) else {
            return nil
        }
        return configuration.jumpTakeoffSpeed.value * SwimRule.surfaceJumpHeightScale.squareRoot()
    }
}
