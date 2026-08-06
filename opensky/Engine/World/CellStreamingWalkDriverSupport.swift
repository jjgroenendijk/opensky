// State labels, movement helpers, and failure gates for M4.5 walk driver.

import simd

@MainActor
final class WalkBenchmarkSceneSwapErrorBox {
    var error: (any Error)?
}

nonisolated enum WalkBenchmarkPhase: CustomStringConvertible {
    case loadExterior
    case settleStart
    case walkExterior(Int)
    case requestEntry
    case waitInterior
    case settleInterior
    case crossInterior
    case returnInterior
    case requestExit
    case waitExterior
    case settleExteriorReturn

    var description: String {
        switch self {
        case .loadExterior: "initial exterior settlement"
        case .settleStart: "start grounding"
        case let .walkExterior(index): "exterior waypoint \(index)"
        case .requestEntry: "farm entry activation"
        case .waitInterior: "farm interior load"
        case .settleInterior: "interior arrival grounding"
        case .crossInterior: "interior floor crossing"
        case .returnInterior: "interior return crossing"
        case .requestExit: "farm exit activation"
        case .waitExterior: "exterior return load"
        case .settleExteriorReturn: "exterior return grounding"
        }
    }

    var physicsActive: Bool {
        if case .loadExterior = self {
            return false
        }
        return true
    }
}

nonisolated struct WalkBenchmarkControllerSnapshot {
    let position: SIMD3<Float>
    let isGrounded: Bool
    let hasUnresolvedPenetration: Bool
}

nonisolated struct WalkBenchmarkControllerState {
    private static let maximumAirborneFrames = 15

    var lastGroundedHeight: Float?
    private(set) var airborneFrames = 0

    mutating func validate(
        phase: WalkBenchmarkPhase,
        snapshot: WalkBenchmarkControllerSnapshot,
        capsule: PlayerCapsule = .standard
    ) throws {
        if snapshot.hasUnresolvedPenetration {
            throw CellStreamingWalkBenchmarkError.unresolvedPenetration(
                phase.description,
                snapshot.position
            )
        }
        if snapshot.isGrounded {
            lastGroundedHeight = snapshot.position.z
            airborneFrames = 0
        } else {
            airborneFrames += 1
        }
        let fellBelowGround = lastGroundedHeight.map {
            snapshot.position.z < $0 - capsule.height
        } ?? false
        if airborneFrames > Self.maximumAirborneFrames, fellBelowGround {
            throw CellStreamingWalkBenchmarkError.fallThrough(
                phase.description,
                snapshot.position
            )
        }
    }
}

nonisolated struct WalkBenchmarkNavigationState {
    private static let minimumProgress: Float = 2
    private static let maximumStalledFrames = 20
    private static let avoidanceDurationFrames = 36

    private(set) var bestDistance = Float.greatestFiniteMagnitude
    private(set) var stalledFrames = 0
    var avoidanceFrames = 0
    private(set) var avoidanceAttempt = 0
    private(set) var avoidanceDirection: Float = 1

    mutating func update(distance: Float, routeIndex: Int) {
        if distance < bestDistance - Self.minimumProgress {
            bestDistance = distance
            stalledFrames = 0
        } else {
            stalledFrames += 1
        }
        guard avoidanceFrames == 0, stalledFrames >= Self.maximumStalledFrames else {
            return
        }
        avoidanceDirection = (routeIndex + avoidanceAttempt).isMultiple(of: 2) ? 1 : -1
        avoidanceAttempt += 1
        avoidanceFrames = Self.avoidanceDurationFrames
        stalledFrames = 0
    }
}

nonisolated enum WalkBenchmarkStateMachine {
    static func validateTimeout(
        phaseFrames: Int,
        limit: Int,
        phase: WalkBenchmarkPhase,
        position: SIMD3<Float>
    ) throws {
        guard phaseFrames < limit else {
            throw CellStreamingWalkBenchmarkError.routeTimedOut(
                phase.description,
                position
            )
        }
    }
}

@MainActor
extension CellStreamingWalkDriver {
    func drive(toward target: SIMD2<Float>, routeIndex: Int) {
        updateNavigationProgress(distance: distance(to: target), routeIndex: routeIndex)
        renderer.freeFlyCamera.yaw = WalkPathRoute.yaw(from: currentXY, to: target)
        if navigationState.avoidanceFrames > 0 {
            updateController(moveForward: 0.5, moveRight: navigationState.avoidanceDirection)
            navigationState.avoidanceFrames -= 1
        } else {
            updateController(moveForward: 1)
        }
    }

    func updateNavigationProgress(distance: Float, routeIndex: Int) {
        navigationState.update(distance: distance, routeIndex: routeIndex)
    }

    func updateController(moveForward: Float, moveRight: Float = 0) {
        renderer.walkController.update(
            camera: &renderer.freeFlyCamera,
            input: CameraInput(
                moveForward: moveForward,
                moveRight: moveRight,
                boost: moveForward != 0,
                dt: Self.inputTimeStep
            ),
            sampleGround: streamer.sampleTerrain,
            collisionQuery: streamer.collisionCandidates
        )
    }

    func validateController() throws {
        let position = renderer.walkController.feetPosition
        try controllerState.validate(
            phase: phase,
            snapshot: WalkBenchmarkControllerSnapshot(
                position: position,
                isGrounded: renderer.walkController.isGrounded,
                hasUnresolvedPenetration: renderer.walkController.hasUnresolvedPenetration
            ),
            capsule: renderer.walkController.capsule
        )
    }

    func validateBuildsAndSwap() throws {
        if let error = swapError.error {
            throw CellStreamingWalkBenchmarkError.sceneSwapFailed(error)
        }
        if streamer.failedCellCount > 0 {
            throw CellStreamingWalkBenchmarkError.cellBuildFailed(streamer.failedCellCount)
        }
        if streamer.doorTransitionFailureCount > 0 {
            throw CellStreamingWalkBenchmarkError.doorBuildFailed(
                streamer.doorTransitionFailureCount
            )
        }
    }

    func timeout(limit: Int) throws {
        try WalkBenchmarkStateMachine.validateTimeout(
            phaseFrames: phaseFrames,
            limit: limit,
            phase: phase,
            position: renderer.walkController.feetPosition
        )
    }

    func changePhase(_ next: WalkBenchmarkPhase) {
        phase = next
        phaseFrames = 0
        navigationState = WalkBenchmarkNavigationState()
    }

    var currentXY: SIMD2<Float> {
        let position = renderer.walkController.feetPosition
        return SIMD2(position.x, position.y)
    }

    func distance(to target: SIMD2<Float>) -> Float {
        simd_distance(currentXY, target)
    }

    static func isSettled(_ streamer: CellStreamer) -> Bool {
        streamer.resolvedCellCount == streamer.desiredCellCount
            && streamer.inFlightCellCount == 0
            && streamer.pendingCompletionCount == 0
            && streamer.queuedRequestCount == 0
    }
}
