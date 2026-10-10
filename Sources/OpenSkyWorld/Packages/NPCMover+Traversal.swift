// The parts of a mover's step that leave plain walking: the gait and speed plan,
// swimming, ledge hops, gliding without ground, and the cell hand-off.

import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

struct NPCMoverStepPlan {
    let speed: Float
    let gait: LocomotionGait
    let yaw: Float
}

extension NPCMover {
    /// Water deep enough to swim, with the player's enter and exit depths, so an actor
    /// does not flicker between swimming and wading at the edge.
    func swimSurface(world: NPCMovementWorld) -> Float? {
        let feet = controller.feetPosition
        guard let surface = world.sampleWater(SIMD2(feet.x, feet.y)), surface.isFinite else {
            return nil
        }
        let threshold = isSwimming
            ? LocomotionBridge.swimExitDepth : LocomotionBridge.swimEnterDepth
        return surface - feet.z >= threshold ? surface : nil
    }

    /// Moves the actor along its ledge arc. The controller restarts at the landing.
    mutating func continueHop(frameTime: Float) {
        guard var current = hop else { return }
        current.advance(by: frameTime)
        controller.reset(cameraPosition: current.feetPosition + SIMD3(0, 0, capsule.eyeHeight))
        hop = current.isFinished ? nil : current
    }

    /// Without loaded ground there is nothing to stand on, so the actor slides along
    /// its path line instead of falling, as an actor out of the loaded area does.
    mutating func glide(toward waypoint: SIMD3<Float>, distance: Float) {
        let feet = controller.feetPosition
        let remaining = waypoint - feet
        let horizontal = simd_length(SIMD2(remaining.x, remaining.y))
        let fraction = horizontal > 0 ? min(1, distance / horizontal) : 1
        let moved = feet + remaining * fraction
        controller.reset(cameraPosition: moved + SIMD3(0, 0, capsule.eyeHeight))
    }

    func stepPlan(frameTime: Float) -> NPCMoverStepPlan {
        let waypoint = path.waypoints[waypointIndex]
        let delta = SIMD2(
            waypoint.x - controller.feetPosition.x,
            waypoint.y - controller.feetPosition.y
        )
        let distance = simd_length(delta)
        let nextGait: LocomotionGait = isSwimming
            ? .swim : distance > NPCMovementRuntime.runDistance ? .run : .walk
        let speed = switch nextGait {
        case .swim: configuration.swimSpeed.value
        case .run: configuration.runSpeed.value
        default: configuration.walkSpeed.value
        }
        let targetYaw = distance > 0 ? atan2f(delta.y, delta.x) : yaw
        let turnedYaw = NPCYawMath.turn(
            from: yaw,
            to: targetYaw,
            maximum: NPCMovementRuntime.maximumYawSpeed * max(frameTime, 0)
        )
        return NPCMoverStepPlan(
            speed: speed,
            gait: nextGait,
            yaw: turnedYaw
        )
    }

    mutating func startHopIfLedge() {
        guard
            path.ledgeCrossings.contains(where: { $0.waypointIndex == waypointIndex }),
            path.waypoints.indices.contains(waypointIndex + 1)
        else { return }
        hop = NPCLedgeHop(
            from: controller.feetPosition,
            landing: path.waypoints[waypointIndex + 1],
            speed: configuration.runSpeed.value
        )
    }

    mutating func collectCellHandoff(
        world: NPCMovementWorld,
        into emissions: inout NPCMoverEmissions
    ) {
        let next = world.cellAt(controller.feetPosition)
        guard let previous = currentCell else {
            currentCell = next
            return
        }
        guard let next, previous != next else { return }
        currentCell = next
        emissions.persistence.append(persistence(reason: .cellHandoff))
    }
}
