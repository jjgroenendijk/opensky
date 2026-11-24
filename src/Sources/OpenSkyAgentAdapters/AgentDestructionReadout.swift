// `state destruction`: the destructible objects near the player, the newest explosions,
// the placed runes, and whether a kill cam plays. docs/engine/papyrus-destruction.md,
// explosions.md, kill-cam.md.

import OpenSkyAgentControl
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyMagicInterface
public import OpenSkySessionInterface
import OpenSkyWorldState
import simd

/// What `state destruction` reads from the session.
@MainActor
public protocol AgentDestructionHost: AnyObject, SendableMetatype {
    var cinematicCamera: any CinematicCameraPort { get }
    var combat: any CombatPort { get }
    var magic: any MagicPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

struct AgentDestructionReadout {
    /// The objects listed are those within this distance of the player.
    static let objectRadius: Float = 4096

    let game: any AgentDestructionHost

    func destructionState() -> AgentJSON {
        [
            "objects": .array(objects()),
            "explosions": .array(game.combat.explosions.reports.map(explosion)),
            "runes": .array(game.magic.runeMarkers.map { rune in
                [
                    "position": .init(rune.position),
                    "projectile": rune.projectile.map { .string($0.description) } ?? .null,
                    "lit": .bool(rune.isLit)
                ]
            }),
            "killCamPlaying": .bool(game.cinematicCamera.isPlaying)
        ]
    }

    private func objects() -> [AgentJSON] {
        guard let bridge = game.scripts.bridge else { return [] }
        let player = game.combat.meleeAttacker.feet
        let streamer = game.streamer
        let entries = streamer.interiorScene.map { $0.references.sortedEntries() }
            ?? streamer.composition.cells.values.flatMap { $0.references.sortedEntries() }
        return entries.compactMap { entry -> AgentJSON? in
            guard
                let placed = entry.placedReference,
                simd_distance(placed.placement.position, player) <= Self.objectRadius,
                let health = bridge.destructionHealthLeft(of: entry.key)
            else { return nil }
            let damage = game.worldState.component(ReferenceDamageModel.self, for: entry.key)
            return [
                "ref": .string(entry.key.description), "healthLeft": .init(health),
                "model": damage?.path.map(AgentJSON.string) ?? .null,
                "damageStage": damage?.stage.map { AgentJSON($0) } ?? .null
            ]
        }
    }

    private func explosion(_ report: ExplosionReport) -> AgentJSON {
        func keyed(_ values: [ReferenceKey: Float]) -> AgentJSON {
            var object: [String: AgentJSON] = [:]
            for (key, value) in values {
                object[key.description] = .init(value)
            }
            return .object(object)
        }
        return [
            "name": .string(report.name), "cause": .string("\(report.cause)"),
            "position": .init(report.position), "damaged": keyed(report.damaged),
            "shielded": .array(report.shielded.map { .string($0.description) }),
            "objectsDamaged": keyed(report.objectsDamaged),
            "objectPlaced": .bool(report.objectPlaced), "debrisThrown": .init(report.debrisThrown)
        ]
    }
}
