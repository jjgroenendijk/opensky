// One actor's path-following state machine. Split from NPCMovementRuntime so
// the crowd registry and one mover remain independently readable.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import simd

public struct NPCMover {
    public let actor: ReferenceKey
    public let formID: FormID
    public let scale: Float
    public let capsule: PlayerCapsule
    /// Where the current cell build draws the actor, which the draw delta starts from.
    public internal(set) var authoredPlacement: PlacedReference.Placement
    let configuration: PlayerMovementConfiguration
    public var controller: WalkController
    public var path: NavigationPath
    public var waypointIndex = 0
    public var yaw: Float
    public var gait: LocomotionGait = .walk
    public var state: NPCMovementState = .moving
    public var repathCount = 0
    private var secondsWithoutProgress: Float = 0
    private var bestWaypointDistance: Float = .greatestFiniteMagnitude
    private var occupiedTriggers: Set<ReferenceKey> = []
    public var currentCell: CellSceneLocation?
    public let ignoresStatics: Bool
    /// The other actors near this one for the step in progress.
    private var neighbours: [NPCNeighbour] = []
    /// The jump across a ledge link in progress.
    public internal(set) var hop: NPCLedgeHop?
    public private(set) var isSwimming = false

    /// `drawnPlacement` is where the cell build drew the actor, when that is not
    /// where it starts: an actor parked since the last build of its cell.
    public init(start: NPCMoveStart, drawnPlacement: PlacedReference.Placement? = nil) {
        actor = start.actor
        formID = start.formID
        scale = start.scale
        capsule = start.capsule
        authoredPlacement = drawnPlacement ?? start.placement
        configuration = start.configuration
        path = start.path
        ignoresStatics = start.ignoresStatics
        yaw = NPCYawMath.yaw(fromHeading: start.placement.rotation.z)
        controller = WalkController(
            cameraPosition: start.placement.position + SIMD3(0, 0, start.capsule.eyeHeight),
            capsule: start.capsule,
            configuration: start.configuration
        )
        advancePastReachedWaypoints()
    }

    public mutating func advance(
        by frameTime: Float,
        world: NPCMovementWorld,
        neighbours: [NPCNeighbour] = []
    ) -> NPCMoverAdvanceOutcome {
        self.neighbours = neighbours
        defer { self.neighbours = [] }
        var emissions = NPCMoverEmissions()
        guard state == .moving || state == .awaitingRepath else {
            return NPCMoverAdvanceOutcome(emissions: emissions, isFinished: true)
        }
        advancePastReachedWaypoints()
        guard waypointIndex < path.waypoints.count else {
            finish(.arrived, reason: .arrival, emissions: &emissions)
            return NPCMoverAdvanceOutcome(emissions: emissions, isFinished: true)
        }

        let feet = controller.feetPosition
        let water = swimSurface(world: world)
        isSwimming = water != nil
        let step = stepPlan(frameTime: frameTime)
        yaw = step.yaw
        gait = step.gait
        let waypoint = path.waypoints[waypointIndex]
        if hop != nil {
            continueHop(frameTime: frameTime)
        } else if world.hasGround(SIMD2(feet.x, feet.y)) {
            walk(
                toward: waypoint, step: step, swimSurface: water,
                frameTime: frameTime, world: world
            )
        } else {
            glide(toward: waypoint, distance: step.speed * max(frameTime, 0))
        }
        emissions.drive = NPCLocomotionDriveUpdate(
            actor: actor,
            intent: LocomotionIntent(moveForward: 1, run: gait == .run),
            gait: gait
        )
        collectTriggerEdges(world: world, into: &emissions)
        collectCellHandoff(world: world, into: &emissions)
        advancePastReachedWaypoints(emissions: &emissions)
        if waypointIndex >= path.waypoints.count {
            finish(.arrived, reason: .arrival, emissions: &emissions)
        } else if hop == nil {
            recoverIfStuck(frameTime: frameTime, world: world, emissions: &emissions)
        }
        return NPCMoverAdvanceOutcome(
            emissions: emissions,
            isFinished: state == .arrived || state == .gaveUp
        )
    }

    private mutating func walk(
        toward waypoint: SIMD3<Float>,
        step: NPCMoverStepPlan,
        swimSurface: Float?,
        frameTime: Float,
        world: NPCMovementWorld
    ) {
        let neighbours = neighbours
        let radius = capsule.radius
        controller.update(
            frameTime: frameTime,
            yaw: yaw,
            sampleGround: ignoresStatics ? staticFloorSampler(world: world) : world.sampleGround,
            collisionQuery: ignoresStatics ? { _ in [] } : world.collisionQuery
        ) { state in
            var plan = LocomotionStepPlan()
            let remaining = SIMD2(
                waypoint.x - state.feetPosition.x,
                waypoint.y - state.feetPosition.y
            )
            let wanted = min(step.speed * state.dt, simd_length(remaining))
            let direction = simd_length(remaining) > 0
                ? NPCAvoidance.steer(
                    direction: remaining,
                    from: SIMD2(state.feetPosition.x, state.feetPosition.y),
                    radius: radius,
                    neighbours: neighbours
                ) : .zero
            plan.horizontalDisplacement = direction * wanted
            plan.swimSurfaceHeight = swimSurface
            plan.motionSource = wanted > 0 ? .configuredSpeed : .idle
            return plan
        }
    }

    private mutating func advancePastReachedWaypoints() {
        var emissions = NPCMoverEmissions()
        advancePastReachedWaypoints(emissions: &emissions)
    }

    /// Near on the ground, and within one capsule height up or down. A patrol marker
    /// can float above the ground, and a waypoint on the floor above is not reached.
    private func isReached(_ waypoint: SIMD3<Float>) -> Bool {
        let feet = controller.feetPosition
        let flatFeet = SIMD2(feet.x, feet.y)
        let flatWaypoint = SIMD2(waypoint.x, waypoint.y)
        // A swimmer floats over a waypoint on the bed below it.
        guard isSwimming || abs(feet.z - waypoint.z) <= capsule.height else { return false }
        return simd_distance(flatFeet, flatWaypoint) <= NPCMovementRuntime.waypointTolerance
            || NPCAvoidance.isTaken(
                flatWaypoint, from: flatFeet, radius: capsule.radius,
                tolerance: NPCMovementRuntime.waypointTolerance, neighbours: neighbours
            )
    }

    private mutating func advancePastReachedWaypoints(
        emissions: inout NPCMoverEmissions
    ) {
        while waypointIndex < path.waypoints.count, hop == nil {
            let waypoint = path.waypoints[waypointIndex]
            guard isReached(waypoint) else { break }
            startHopIfLedge()
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
            gait: .walk
        )
        emissions.persistence.append(persistence(reason: reason))
        emissions.triggers += occupiedTriggers.sorted().map {
            TriggerTransitionEvent(reference: $0, phase: .leave, actor: actor)
        }
        occupiedTriggers.removeAll()
    }
}
