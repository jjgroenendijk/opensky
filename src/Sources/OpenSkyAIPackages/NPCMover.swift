// One actor's path-following state machine. Split from NPCMovementRuntime so
// the crowd registry and one mover remain independently readable.

public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyPhysics
public import OpenSkyPlayer
public import OpenSkyWorldInterface
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
    /// Where `currentCell` was last looked up.
    var cellCheckedAt: SIMD3<Float>?
    public let ignoresStatics: Bool
    public let preferredGait: LocomotionGait?
    let runSlowdown: FollowSettings?
    let walkRunBlend: Float?
    let longBody: LongBodyShape?
    /// This step's movement type speeds, from the actor's graph state.
    var movementSpeeds: MovementType.Speeds?
    /// The other actors near this one for the step in progress.
    private(set) var neighbours: [NPCNeighbour] = []
    /// The jump across a ledge link in progress.
    public internal(set) var hop: NPCLedgeHop?
    public private(set) var isSwimming = false
    /// Where the current leg began: the start, the last reached waypoint, or a repath.
    private(set) var legStart: SIMD3<Float>

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
        preferredGait = start.gait
        runSlowdown = start.runSlowdown
        walkRunBlend = start.walkRunBlend
        longBody = start.longBody
        legStart = start.placement.position
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
        let sample = world.sampleWater(feet)
        let water = swimSurface(sample)
        isSwimming = water != nil
        movementSpeeds = world.movementSpeeds(actor)
        let step = stepPlan(frameTime: frameTime)
        yaw = step.yaw
        gait = step.gait
        let waypoint = path.waypoints[waypointIndex]
        if hop != nil {
            continueHop(frameTime: frameTime)
        } else if world.hasGround(SIMD2(feet.x, feet.y)) {
            walk(
                toward: waypoint, pace: (step, frameTime), water: (sample, water), world: world
            )
        } else {
            glide(toward: waypoint, distance: step.speed * max(frameTime, 0))
        }
        emissions.landing = controller.takeLanding()
        emissions.drive = NPCLocomotionDriveUpdate(
            actor: actor,
            intent: LocomotionIntent(moveForward: 1, run: gait == .run),
            gait: gait,
            groundMaterial: controller.groundMaterial
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
        pace: (step: NPCMoverStepPlan, frameTime: Float),
        water: (sample: WaterReading?, swimSurface: Float?),
        world: NPCMovementWorld
    ) {
        let (step, frameTime) = pace
        let neighbours = neighbours
        let radius = capsule.radius
        let race = world.waterPushRace(actor)
        let configuration = configuration
        let query: WalkController.CollisionQuery = ignoresStatics
            ? { _ in [] } : world.collisionQuery(for: actor)
        let (longBody, yaw) = (longBody, yaw)
        controller.update(
            frameTime: frameTime,
            yaw: yaw,
            sampleGround: ignoresStatics ? staticFloorSampler(world: world) : world.sampleGround,
            collisionQuery: query
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
            if let longBody {
                plan.horizontalDisplacement += longBody.correction(
                    pose: (state.feetPosition, yaw), displacement: plan.horizontalDisplacement,
                    lift: configuration.stepHeight.value, query: query
                )
            }
            plan.swimSurfaceHeight = water.swimSurface
            plan.motionSource = wanted > 0 ? .configuredSpeed : .idle
            plan.applyCurrent(
                water.sample, state: state, configuration: configuration, race: race
            )
            return plan
        }
    }

    private mutating func advancePastReachedWaypoints() {
        var emissions = NPCMoverEmissions()
        advancePastReachedWaypoints(emissions: &emissions)
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
            legStart = waypoint
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
        legStart = controller.feetPosition
        state = .moving
        bestWaypointDistance = .greatestFiniteMagnitude
        secondsWithoutProgress = 0
        advancePastReachedWaypoints(emissions: &emissions)
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

extension NPCMover {
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
}
