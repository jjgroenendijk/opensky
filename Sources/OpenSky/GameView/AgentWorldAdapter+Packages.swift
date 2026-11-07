// The answer to `openskycli game state packages`, from the package runtime and the
// procedure machine the AI readout reads, the vehicle the actor rides, and its last idle.

import Foundation
import OpenSkyActorPresentation
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension AgentWorldAdapter {
    func packagesState(reference: String) throws(AgentFailure) -> AgentJSON {
        let key = try resolveReference(reference).key
        let readout = game.packages.readout(for: key)
        let machine = game.packages.executions[key]?.machine
        let mover = game.streamer?.npcMovementReadouts().first { $0.actor == key }
        let links = game.vehicleWorld.vehicles.core.links
        return [
            "package": readout?.editorID.map(AgentJSON.string) ?? .null,
            "procedure": readout?.procedure.map { .string("\($0)") } ?? .null,
            "evaluatedAt": readout?.lastEvaluationGameSeconds
                .map { .string(String(format: "%.1f", $0)) } ?? .null,
            "override": readout?.override.map { .string("\($0)") } ?? .null,
            "state": machine.map { .string("\($0.state)") } ?? .null,
            "pathIndex": machine.map { .init($0.pathIndex) } ?? .null,
            "pathCount": machine.map { .init($0.path.count) } ?? .null,
            "running": .array((game.packages.executions[key]?.runner.runningMachines ?? [])
                .map { .string("\($0.kind.name) \($0.state)") }),
            "carrier": game.vehicleWorld.vehicles.core.links[key]
                .map { .string("\($0.carrier)") } ?? .null,
            "mover": mover.map {
                .string("\($0.state) waypoint \($0.waypointIndex) of \($0.waypointCount)"
                    + " at \($0.feetPosition)")
            } ?? .null,
            "movement": movementReadout(key),
            "vehicle": vehicleReadout(key),
            "vehicleLinks": .array(links.keys.sorted()
                .map { .string("\($0) -> \(links[$0]?.carrier as Any)") }),
            "lastMove": game.packages.lastMoves[key].map { .string("\($0)") } ?? .null,
            "walk": key == .player ? .array((game.gameSession?.playerWalkPath ?? []).map {
                .string("\($0.x.rounded()), \($0.y.rounded()), \($0.z.rounded())")
            }) : .null,
            "idle": game.idleWorld.idles.idleSnapshot(for: key).report.map {
                .string("\($0.chosen ?? "none") from \($0.source) "
                    + ($0.seconds.isFinite ? "for \($0.seconds) s" : "held")
                    + ($0.failure.map { ", failed: \($0)" } ?? ""))
            } ?? .null,
            "idleTrace": .array((game.idleWorld.idles.idleSnapshot(for: key).report?.trace ?? [])
                .map { .string(IdleReadout.traceLine($0)) })
        ]
    }

    /// The movement type the actor's graph names, its speeds, and the shape it collides as.
    private func movementReadout(_ key: ReferenceKey) -> AgentJSON {
        let name = game.actorGraphs.movementStateName(of: key)
        let speeds = game.streamer?.npcMovementSpeeds?(key)
        let scale = game.streamer?.npcTransform(for: key)?.scale ?? 1
        let bounds = game.streamer?.npcBodyHalfExtents?(key)
        let capsule = bounds.flatMap { PlayerCapsule.upright(halfExtents: $0, scale: scale) }
        let long = bounds.flatMap { LongBodyShape(halfExtents: $0, scale: scale) }
        return [
            "type": name.map(AgentJSON.string) ?? .null,
            "walk": speeds.map { .init($0.forwardWalk * scale) } ?? .null,
            "run": speeds.map { .init($0.forwardRun * scale) } ?? .null,
            "capsuleRadius": capsule.map { .init($0.radius) } ?? .null,
            "capsuleHeight": capsule.map { .init($0.height) } ?? .null,
            "endRadius": long.map { .init($0.endRadius) } ?? .null,
            "endOffset": long.map { .init($0.endOffset) } ?? .null
        ]
    }

    /// Where the vehicle pass puts `key`, and which cell draws it at which pose.
    private func vehicleReadout(_ key: ReferenceKey) -> AgentJSON {
        guard let live = game.vehicleWorld.vehicles.lastPoses[key] else { return .null }
        let built = game.vehicleWorld.vehicleFormID(of: key)
            .flatMap { game.renderer?.scene.referencePlacements[$0]?.columns.3 }
        let head = game.idleWorld.idles.idleBone(of: key, named: DialogueCamera.headBoneName)
            .map { bone in
                let root = MatrixMath.placement(
                    position: live.position, rotation: live.rotation, scale: 1
                )
                let world = root * SIMD4(bone, 1)
                return SIMD3(world.x, world.y, world.z)
            }
        return [
            "head": head.map { .init($0) } ?? .null,
            "live": .init(live.position),
            "yaw": .init(live.rotation.z),
            "cell": game.streamer?.cellLocation(of: key).map { .string("\($0)") } ?? .null,
            "built": built.map { .init(SIMD3($0.x, $0.y, $0.z)) } ?? .null
        ]
    }
}
