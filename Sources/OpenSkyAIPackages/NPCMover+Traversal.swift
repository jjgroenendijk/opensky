// The parts of a mover's step that leave plain walking: the gait and speed plan,
// swimming, ledge hops, gliding without ground, and the cell hand-off.

import OpenSkyNavigation
import OpenSkyPhysics
import OpenSkyPlayer
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

    func speed(of gait: LocomotionGait) -> Float {
        switch gait {
        case .swim: configuration.swimSpeed.value
        case .run: configuration.runSpeed.value
        case .sprint: configuration.sprintSpeed.value
        case .sneak: configuration.sneakSpeed.value
        case .walk: configuration.walkSpeed.value
        }
    }

    func stepPlan(frameTime: Float) -> NPCMoverStepPlan {
        let waypoint = path.waypoints[waypointIndex]
        let delta = SIMD2(
            waypoint.x - controller.feetPosition.x,
            waypoint.y - controller.feetPosition.y
        )
        let distance = simd_length(delta)
        let byLeg: LocomotionGait = distance > NPCMovementRuntime.runDistance ? .run : .walk
        let nextGait = isSwimming ? .swim : preferredGait ?? byLeg
        var speed = speed(of: nextGait)
        if let walkRunBlend, !isSwimming {
            let walk = configuration.walkSpeed.value
            speed = walk + (configuration.runSpeed.value - walk) * walkRunBlend
        }
        if
            let runSlowdown, nextGait == .run || nextGait == .sprint,
            waypointIndex == path.waypoints.count - 1
        {
            speed *= runSlowdown.runSpeedScale(
                remaining: distance, slowingDistance: NPCMovementRuntime.runDistance
            )
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

    /// Travel between cell lookups. Near the target every step looks, so the arrival
    /// write names the cell the actor ends in.
    static let cellCheckSpacing: Float = 32

    mutating func collectCellHandoff(
        world: NPCMovementWorld,
        into emissions: inout NPCMoverEmissions
    ) {
        let feet = controller.feetPosition
        if
            let checked = cellCheckedAt,
            simd_distance(checked, feet) < Self.cellCheckSpacing,
            simd_distance(path.target, feet) > Self.cellCheckSpacing
        {
            return
        }
        cellCheckedAt = feet
        let next = world.cellAt(feet)
        guard let previous = currentCell else {
            currentCell = next
            return
        }
        guard let next, previous != next else { return }
        currentCell = next
        emissions.persistence.append(persistence(reason: .cellHandoff))
    }
}
