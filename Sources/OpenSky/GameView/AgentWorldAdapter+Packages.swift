// The answer to `openskycli game state packages`, from the package runtime and the
// procedure machine the AI panel reads, the vehicle the actor rides, and its last idle.

import Foundation
import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyWorld

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
            "carrier": game.vehicleWorld.vehicles.core.links[key]
                .map { .string("\($0.carrier)") } ?? .null,
            "mover": mover.map {
                .string("\($0.state) waypoint \($0.waypointIndex) of \($0.waypointCount)"
                    + " at \($0.feetPosition)")
            } ?? .null,
            "vehicleLinks": .array(links.keys.sorted()
                .map { .string("\($0) -> \(links[$0]?.carrier as Any)") }),
            "lastMove": game.aiWorld.lastPackageMoves[key].map { .string("\($0)") } ?? .null,
            "walk": key == .player ? .array((game.renderer?.playerWalkPath ?? []).map {
                .string("\($0.x.rounded()), \($0.y.rounded()), \($0.z.rounded())")
            }) : .null,
            "idle": game.idleWorld.idles.idleSnapshot(for: key).report.map {
                .string("\($0.chosen ?? "none") from \($0.source) for \($0.seconds) s"
                    + ($0.failure.map { ", failed: \($0)" } ?? ""))
            } ?? .null
        ]
    }
}
