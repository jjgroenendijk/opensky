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

@MainActor
extension CellStreamingWalkDriver {
    func drive(toward target: SIMD2<Float>, routeIndex: Int) {
        updateNavigationProgress(distance: distance(to: target), routeIndex: routeIndex)
        renderer.freeFlyCamera.yaw = WalkPathRoute.yaw(from: currentXY, to: target)
        if avoidanceFrames > 0 {
            updateController(moveForward: 0.5, moveRight: avoidanceDirection)
            avoidanceFrames -= 1
        } else {
            updateController(moveForward: 1)
        }
    }

    func updateNavigationProgress(distance: Float, routeIndex: Int) {
        if distance < bestNavigationDistance - 2 {
            bestNavigationDistance = distance
            stalledNavigationFrames = 0
        } else {
            stalledNavigationFrames += 1
        }
        guard avoidanceFrames == 0, stalledNavigationFrames >= 20 else { return }
        avoidanceDirection = (routeIndex + avoidanceAttempt).isMultiple(of: 2) ? 1 : -1
        avoidanceAttempt += 1
        avoidanceFrames = 36
        stalledNavigationFrames = 0
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
        if renderer.walkController.hasUnresolvedPenetration {
            throw CellStreamingWalkBenchmarkError.unresolvedPenetration(
                phase.description,
                position
            )
        }
        if renderer.walkController.isGrounded {
            lastGroundedHeight = position.z
            airborneFrames = 0
        } else {
            airborneFrames += 1
        }
        let fellBelowGround = lastGroundedHeight.map {
            position.z < $0 - PlayerCapsule.standard.height
        } ?? false
        if airborneFrames > 15, fellBelowGround {
            throw CellStreamingWalkBenchmarkError.fallThrough(phase.description, position)
        }
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
        guard phaseFrames < limit else {
            throw CellStreamingWalkBenchmarkError.routeTimedOut(
                phase.description,
                renderer.walkController.feetPosition
            )
        }
    }

    func changePhase(_ next: WalkBenchmarkPhase) {
        phase = next
        phaseFrames = 0
        bestNavigationDistance = Float.greatestFiniteMagnitude
        stalledNavigationFrames = 0
        avoidanceFrames = 0
        avoidanceAttempt = 0
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
