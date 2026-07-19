// Interior crossing + paired exterior return for M4.5 walk benchmark.

import simd

@MainActor
extension CellStreamingWalkDriver {
    func waitInterior() throws {
        updateController(moveForward: 0)
        streamer.update(cameraPosition: renderer.freeFlyCamera.position)
        try validateController()
        guard let interior = streamer.interiorScene else {
            try timeout(limit: WalkPathRoute.maximumTransitionFrames)
            return
        }
        guard interior.location == .interior(WalkPathRoute.farmInterior) else {
            throw CellStreamingWalkBenchmarkError.wrongDestination(
                "expected interior \(WalkPathRoute.farmInterior), got "
                    + "\(String(describing: interior.location))"
            )
        }
        changePhase(.settleInterior)
    }

    func settleInterior() throws {
        updateController(moveForward: 0)
        streamer.update(cameraPosition: renderer.freeFlyCamera.position)
        try validateController()
        guard renderer.walkController.isGrounded else {
            try timeout(limit: 120)
            return
        }
        let arrival = currentXY
        interiorArrival = arrival
        interiorTarget = WalkPathRoute.interiorTarget(
            from: arrival,
            yaw: renderer.freeFlyCamera.yaw
        )
        changePhase(.crossInterior)
    }

    func crossInterior() throws {
        guard let target = interiorTarget, let arrival = interiorArrival else {
            throw CellStreamingWalkBenchmarkError.wrongDestination("missing interior route")
        }
        drive(toward: target, routeIndex: 100)
        streamer.update(cameraPosition: renderer.freeFlyCamera.position)
        try validateController()
        interiorDistance = max(interiorDistance, simd_distance(arrival, currentXY))
        guard distance(to: target) <= WalkPathRoute.waypointTolerance else {
            try timeout(limit: WalkPathRoute.maximumWaypointFrames)
            return
        }
        changePhase(.returnInterior)
    }

    func returnInterior() throws {
        guard let target = interiorArrival else {
            throw CellStreamingWalkBenchmarkError.wrongDestination("missing arrival pose")
        }
        drive(toward: target, routeIndex: 101)
        streamer.update(cameraPosition: renderer.freeFlyCamera.position)
        try validateController()
        guard distance(to: target) <= WalkPathRoute.waypointTolerance else {
            try timeout(limit: WalkPathRoute.maximumWaypointFrames)
            return
        }
        changePhase(.requestExit)
    }

    func requestExit() throws {
        let door = streamer.interiorScene.flatMap {
            streamer.nearestDoor(in: $0, to: renderer.freeFlyCamera.position)
        }
        guard door?.reference == WalkPathRoute.interiorDoor else {
            throw CellStreamingWalkBenchmarkError.wrongDoor(
                expected: WalkPathRoute.interiorDoor,
                actual: door?.reference
            )
        }
        streamer.update(cameraPosition: renderer.freeFlyCamera.position, activate: true)
        changePhase(.waitExterior)
    }

    func waitExterior() throws {
        updateController(moveForward: 0)
        streamer.update(cameraPosition: renderer.freeFlyCamera.position)
        try validateController()
        guard !streamer.isInterior else {
            try timeout(limit: WalkPathRoute.maximumTransitionFrames)
            return
        }
        guard streamer.residentCoordinates.contains(WalkPathRoute.farmCell) else {
            throw CellStreamingWalkBenchmarkError.wrongDestination(
                "return did not seed farm exterior cell"
            )
        }
        guard simd_distance(currentXY, WalkPathRoute.exteriorReturn) <= 128 else {
            throw CellStreamingWalkBenchmarkError.wrongDestination(
                "return pose \(currentXY) is not farm exterior"
            )
        }
        changePhase(.settleExteriorReturn)
    }

    func settleExteriorReturn() throws -> Bool {
        updateController(moveForward: 0)
        streamer.update(cameraPosition: renderer.freeFlyCamera.position)
        try validateController()
        guard renderer.walkController.isGrounded else {
            try timeout(limit: 120)
            return false
        }
        return true
    }
}
