// One actor's path-following state machine. Split from NPCMovementRuntime so
// the crowd registry and one mover remain independently readable.

import simd

private struct NPCMoverStepPlan {
    let speed: Float
    let gait: LocomotionGait
    let yaw: Float
}

struct NPCMover {
    let actor: ReferenceKey
    let formID: FormID
    let scale: Float
    let capsule: PlayerCapsule
    let authoredPlacement: PlacedReference.Placement
    private let configuration: PlayerMovementConfiguration
    var controller: WalkController
    var path: NavigationPath
    var waypointIndex = 0
    var yaw: Float
    var gait: LocomotionGait = .walk
    var state: NPCMovementState = .moving
    var repathCount = 0
    private var secondsWithoutProgress: Float = 0
    private var bestWaypointDistance: Float = .greatestFiniteMagnitude
    private var occupiedTriggers: Set<ReferenceKey> = []
    var currentCell: CellSceneLocation?

    init(start: NPCMoveStart) {
        actor = start.actor
        formID = start.formID
        scale = start.scale
        capsule = start.capsule
        authoredPlacement = start.placement
        configuration = start.configuration
        path = start.path
        yaw = start.placement.rotation.z
        controller = WalkController(
            cameraPosition: start.placement.position + SIMD3(0, 0, start.capsule.eyeHeight),
            capsule: start.capsule,
            configuration: start.configuration
        )
        advancePastReachedWaypoints()
    }

    mutating func advance(by frameTime: Float, world: NPCMovementWorld) -> NPCMoverAdvanceOutcome {
        var emissions = NPCMoverEmissions()
        guard state == .moving || state == .awaitingRepath else {
            return NPCMoverAdvanceOutcome(emissions: emissions, isFinished: true)
        }
        advancePastReachedWaypoints()
        guard waypointIndex < path.waypoints.count else {
            finish(.arrived, reason: .arrival, emissions: &emissions)
            return NPCMoverAdvanceOutcome(emissions: emissions, isFinished: true)
        }

        let step = stepPlan(frameTime: frameTime)
        yaw = step.yaw
        gait = step.gait
        let waypoint = path.waypoints[waypointIndex]
        controller.update(
            frameTime: frameTime,
            yaw: yaw,
            sampleGround: world.sampleGround,
            collisionQuery: world.collisionQuery
        ) { state in
            var plan = LocomotionStepPlan()
            let remaining = SIMD2(
                waypoint.x - state.feetPosition.x,
                waypoint.y - state.feetPosition.y
            )
            let wanted = min(step.speed * state.dt, simd_length(remaining))
            plan.horizontalDisplacement = simd_length(remaining) > 0
                ? simd_normalize(remaining) * wanted : .zero
            plan.motionSource = wanted > 0 ? .configuredSpeed : .idle
            return plan
        }
        emissions.drive = NPCLocomotionDriveUpdate(
            actor: actor,
            intent: LocomotionIntent(moveForward: 1, run: gait == .run),
            gait: gait,
            yaw: yaw,
            deltaTime: frameTime
        )
        collectTriggerEdges(world: world, into: &emissions)
        collectCellHandoff(world: world, into: &emissions)
        advancePastReachedWaypoints(emissions: &emissions)
        if waypointIndex >= path.waypoints.count {
            finish(.arrived, reason: .arrival, emissions: &emissions)
        } else {
            recoverIfStuck(frameTime: frameTime, world: world, emissions: &emissions)
        }
        return NPCMoverAdvanceOutcome(
            emissions: emissions,
            isFinished: state == .arrived || state == .gaveUp
        )
    }

    private func stepPlan(frameTime: Float) -> NPCMoverStepPlan {
        let waypoint = path.waypoints[waypointIndex]
        let delta = SIMD2(
            waypoint.x - controller.feetPosition.x,
            waypoint.y - controller.feetPosition.y
        )
        let distance = simd_length(delta)
        let nextGait: LocomotionGait = distance > NPCMovementRuntime.runDistance ? .run : .walk
        let speed = nextGait == .run ? configuration.runSpeed.value : configuration.walkSpeed.value
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

    private mutating func advancePastReachedWaypoints() {
        var emissions = NPCMoverEmissions()
        advancePastReachedWaypoints(emissions: &emissions)
    }

    private mutating func advancePastReachedWaypoints(
        emissions: inout NPCMoverEmissions
    ) {
        while waypointIndex < path.waypoints.count {
            let waypoint = path.waypoints[waypointIndex]
            guard
                simd_distance(controller.feetPosition, waypoint)
                <= NPCMovementRuntime.waypointTolerance else { break }
            if
                let crossing = path.doorCrossings.first(where: {
                    $0.waypointIndex == waypointIndex
                })
            {
                emissions.doors.append((actor, crossing.door))
                if path.waypoints.indices.contains(waypointIndex + 1) {
                    controller.reset(
                        cameraPosition: path.waypoints[waypointIndex + 1]
                            + SIMD3(0, 0, capsule.eyeHeight)
                    )
                    waypointIndex += 1
                }
            }
            waypointIndex += 1
            bestWaypointDistance = .greatestFiniteMagnitude
            secondsWithoutProgress = 0
        }
    }

    private mutating func recoverIfStuck(
        frameTime: Float,
        world: NPCMovementWorld,
        emissions: inout NPCMoverEmissions
    ) {
        let distance = simd_distance(controller.feetPosition, path.waypoints[waypointIndex])
        if distance + NPCMovementRuntime.progressTolerance < bestWaypointDistance {
            bestWaypointDistance = distance
            secondsWithoutProgress = 0
            return
        }
        secondsWithoutProgress += max(frameTime, 0)
        guard secondsWithoutProgress >= NPCMovementRuntime.stuckTimeout else { return }
        guard repathCount == 0 else {
            finish(.gaveUp, reason: .giveUp, emissions: &emissions)
            return
        }
        repathCount = 1
        state = .awaitingRepath
        let result = world.repath(NavigationPathQuery(
            start: controller.feetPosition,
            target: path.target,
            capsuleRadius: capsule.radius
        ))
        guard case let .path(replacement) = result else {
            finish(.gaveUp, reason: .giveUp, emissions: &emissions)
            return
        }
        path = replacement
        waypointIndex = 0
        state = .moving
        bestWaypointDistance = .greatestFiniteMagnitude
        secondsWithoutProgress = 0
        advancePastReachedWaypoints(emissions: &emissions)
    }

    private mutating func collectCellHandoff(
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

    private mutating func collectTriggerEdges(
        world: NPCMovementWorld,
        into emissions: inout NPCMoverEmissions
    ) {
        let current = world.triggersAt(PlayerCapsuleState(
            capsule: capsule, feetPosition: controller.feetPosition
        ))
        let entered = current.subtracting(occupiedTriggers)
        let left = occupiedTriggers.subtracting(current)
        occupiedTriggers = current
        emissions.triggers += entered.sorted().map {
            TriggerTransitionEvent(reference: $0, phase: .enter, actor: actor)
        }
        emissions.triggers += left.sorted().map {
            TriggerTransitionEvent(reference: $0, phase: .leave, actor: actor)
        }
    }

    private mutating func finish(
        _ finalState: NPCMovementState,
        reason: NPCMovementSettleReason,
        emissions: inout NPCMoverEmissions
    ) {
        state = finalState
        gait = .walk
        emissions.drive = NPCLocomotionDriveUpdate(
            actor: actor,
            intent: .still,
            gait: .walk,
            yaw: yaw,
            deltaTime: 0
        )
        emissions.persistence.append(persistence(reason: reason))
        emissions.triggers += occupiedTriggers.sorted().map {
            TriggerTransitionEvent(reference: $0, phase: .leave, actor: actor)
        }
        occupiedTriggers.removeAll()
    }
}
