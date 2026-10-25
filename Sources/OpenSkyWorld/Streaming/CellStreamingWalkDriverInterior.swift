// Interior crossing and paired exterior return for the walk benchmark.

import OpenSkyCells
import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyWorldInterface
import simd

@MainActor
extension CellStreamingWalkDriver {
    public func waitInterior() throws {
        updateController(moveForward: 0)
        updateStreamer()
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

    public func settleInterior() throws {
        updateController(moveForward: 0)
        updateStreamer()
        try validateController()
        guard gameSession.walkController.isGrounded else {
            try timeout(limit: 120)
            return
        }
        let arrival = currentXY
        interiorArrival = arrival
        interiorRoute = WalkPathRoute.interiorWaypoints(
            from: arrival,
            yaw: gameSession.freeFlyCamera.yaw
        )
        interiorRouteIndex = 0
        changePhase(.crossInterior)
    }

    public func crossInterior() throws {
        guard
            interiorRoute.indices.contains(interiorRouteIndex),
            let arrival = interiorArrival
        else {
            throw CellStreamingWalkBenchmarkError.wrongDestination("missing interior route")
        }
        let target = interiorRoute[interiorRouteIndex]
        drive(toward: target, routeIndex: 100 + interiorRouteIndex)
        updateStreamer()
        try validateController()
        interiorDistance = max(interiorDistance, simd_distance(arrival, currentXY))
        guard distance(to: target) <= WalkPathRoute.waypointTolerance else {
            try timeout(limit: WalkPathRoute.maximumWaypointFrames)
            return
        }
        interiorRouteIndex += 1
        if interiorRoute.indices.contains(interiorRouteIndex) {
            changePhase(.crossInterior)
        } else {
            interiorRouteIndex = interiorRoute.count - 2
            changePhase(.returnInterior)
        }
    }

    public func returnInterior() throws {
        guard let arrival = interiorArrival else {
            throw CellStreamingWalkBenchmarkError.wrongDestination("missing arrival pose")
        }
        let target = interiorRoute.indices.contains(interiorRouteIndex)
            ? interiorRoute[interiorRouteIndex]
            : arrival
        drive(toward: target, routeIndex: 200 + max(interiorRouteIndex, 0))
        updateStreamer()
        try validateController()
        guard distance(to: target) <= WalkPathRoute.waypointTolerance else {
            try timeout(limit: WalkPathRoute.maximumWaypointFrames)
            return
        }
        if interiorRouteIndex >= 0 {
            interiorRouteIndex -= 1
            changePhase(.returnInterior)
        } else {
            changePhase(.requestExit)
        }
    }

    public func requestExit() throws {
        let door = streamer.interiorScene.flatMap {
            streamer.nearestDoor(in: $0, to: gameSession.freeFlyCamera.position)
        }
        guard door?.reference == WalkPathRoute.interiorDoor else {
            throw CellStreamingWalkBenchmarkError.wrongDoor(
                expected: WalkPathRoute.interiorDoor,
                actual: door?.reference
            )
        }
        let interactionRay = door.flatMap {
            InteractionRay(
                origin: gameSession.freeFlyCamera.position,
                direction: $0.position - gameSession.freeFlyCamera.position
            )
        }
        updateStreamer(interactionRay: interactionRay, activate: true)
        guard streamer.interactionTarget?.interaction.reference == WalkPathRoute.interiorDoor else {
            throw CellStreamingWalkBenchmarkError.wrongDoor(
                expected: WalkPathRoute.interiorDoor,
                actual: streamer.interactionTarget?.interaction.reference
            )
        }
        changePhase(.waitExterior)
    }

    public func waitExterior() throws {
        updateController(moveForward: 0)
        updateStreamer()
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

    public func settleExteriorReturn() throws -> Bool {
        updateController(moveForward: 0)
        updateStreamer()
        try validateController()
        guard gameSession.walkController.isGrounded else {
            try timeout(limit: 120)
            return false
        }
        return true
    }
}
