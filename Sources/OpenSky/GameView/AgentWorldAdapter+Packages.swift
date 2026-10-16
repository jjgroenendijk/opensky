// The answer to `openskycli game state packages`, from the package runtime and the
// procedure machine the AI panel reads, the vehicle the actor rides, and its last idle.

import Foundation
import OpenSkyAgentControl
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyWorld
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
            "vehicle": vehicleReadout(key),
            "vehicleLinks": .array(links.keys.sorted()
                .map { .string("\($0) -> \(links[$0]?.carrier as Any)") }),
            "lastMove": game.aiWorld.lastPackageMoves[key].map { .string("\($0)") } ?? .null,
            "walk": key == .player ? .array((game.renderer?.playerWalkPath ?? []).map {
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
