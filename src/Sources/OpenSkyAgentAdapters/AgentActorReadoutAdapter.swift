import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AgentActorReadoutAdapter` reads from the session.
@MainActor
public protocol AgentActorReadoutHost: AnyObject {
    var actorGraphs: any ActorGraphPort { get }
    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)?
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var dialogueWorld: any DialogueWorldPort { get }
    var factions: any FactionPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var perception: any PerceptionPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentActorReadoutAdapter {
    public let hub: AgentHub
    public let game: any AgentActorReadoutHost
}

extension AgentActorReadoutAdapter {
    public func cellState(at position: SIMD3<Float>) -> AgentJSON {
        let streamer = game.streamer
        if let interior = streamer.interiorScene {
            return ["interior": true, "name": .string(interior.summary.cellName)]
        }
        let grid = CellCoordinate(containing: position)
        return [
            "interior": false, "x": .init(Int(grid.x)), "y": .init(Int(grid.y)),
            "name": .init(streamer.composition.cells[grid]?.summary.cellName)
        ]
    }

    public func targetState() -> AgentJSON {
        guard let target = game.streamer.interactionTarget else { return .null }
        let interaction = target.interaction
        return [
            "ref": .formID(interaction.reference.rawValue),
            "base": .formID(interaction.base.rawValue),
            "name": .string(interaction.name),
            "action": .string(interaction.actionLabel),
            "distance": .init(target.distance),
            "position": .init(interaction.position),
            "theft": .bool(game.inventory.targetOwnership()?.isTheft == true)
        ]
    }

    public func actorsState(radius: Float) throws(AgentFailure) -> AgentJSON {
        guard let gameSession = game.gameSession else { throw hub.notReady() }
        let origin = gameSession.freeFlyCamera.position
        let rows = game.actorWorld.combatActors().compactMap { actor in
            actorRow(actor, origin: origin, radius: radius)
        }
        return ["actors": .array(rows.sorted { $0.0 < $1.0 }.map(\.1))]
    }

    private func actorRow(
        _ actor: CombatActorObservation, origin: SIMD3<Float>, radius: Float
    ) -> (Float, AgentJSON)? {
        let distance = simd_distance(actor.feet, origin)
        guard distance <= radius else { return nil }
        let entry = game.streamer.referenceEntry(key: actor.key)
        let formID = entry?.formID
        let graph: AgentJSON = game.actorGraphs.readout(for: actor.key).map(graphState) ?? .null
        return (distance, [
            "leveled": leveledState(of: actor.key, base: entry?.placedActor?.base),
            "ref": formID.map { .formID($0.rawValue) } ?? .null,
            "name": .string(game.dialogueWorld.speakerLabel(for: actor.key)),
            "position": .init(actor.feet),
            "distance": .init(distance),
            "dead": .bool(actor.isDead),
            "hostility": .string("\(game.factions.hostility(of: actor.key))"),
            "combat": game.combat.loop?.phase(of: actor.key).map { .string("\($0)") } ?? .null,
            "detects": game.perception.runtime
                .map { .string("\($0.state(observer: actor.key, target: .player).state)") }
                ?? .null,
            "eyeTexture": hub.actors.eyeTexture(of: actor.key),
            "severed": hub.actors.severedState(of: actor.key),
            "soundLoops": .array(
                (game.gameSession?.soundDirector?.actorLoopNames(of: actor.key) ?? [])
                    .map(AgentJSON.string)
            ),
            "skinDecals": .array(hub.render.skinDecalBones(of: actor.key).map(AgentJSON.string)),
            "constraints": hub.actors.physicsConstraints(of: actor.key),
            "lagBones": .object(
                (game.actorPlayback(for: actor.key)?.lagBoneOffsets ?? [:])
                    .mapValues(AgentJSON.init)
            ),
            "graph": graph
        ])
    }

    private func graphState(_ graph: ActorGraphReadout) -> AgentJSON {
        [
            "status": .string(graph.status),
            "project": .string(graph.project),
            "activeStates": .array(graph.activeStates.map(AgentJSON.string)),
            "waitingForClip": .bool(graph.isWaitingForClip),
            "hasPose": .bool(graph.hasPose),
            "steps": .init(graph.steps),
            "rate": .string(graph.rate),
            "recentEvents": .array(graph.recentEvents.map(AgentJSON.string)),
            "unresolvedClips": .array(graph.unresolvedClips.map(AgentJSON.string)),
            "clipsLoaded": .init(graph.clipsLoaded),
            "clipsMissed": .init(graph.clipsMissed),
            "boneLODHeldFrom": .init(graph.heldFromBone),
            "drunk": .bool(graph.isDrunk),
            "iState": graph.state.map { .init(Int($0)) } ?? .null,
            "iStateTag": graph.stateTag.map { .init(Int($0)) } ?? .null,
            "bodyWeight": .object(graph.bodyWeight.mapValues(AgentJSON.init))
        ]
    }

    /// The `LVLN` hops of an actor's template chain, the entry each rolled, and the
    /// encounter level and difficulty the roll read (docs/engine/leveled-lists.md).
    private func leveledState(of key: ReferenceKey, base: FormID?) -> AgentJSON {
        guard
            let base, let templates = game.actorValues.runtime?.baselines.resolver?.templates
        else { return .null }
        let roll = game.worldState.leveledRoll(of: key, base: base, with: templates.leveling)
        guard let chain = attempt({ try templates.rolling(roll).resolve(base: base).chain }) else {
            return .null
        }
        let hops: [AgentJSON] = chain.compactMap { link in
            guard case let .leveled(list, chosen) = link else { return nil }
            return ["list": .formID(list.rawValue), "chosen": .formID(chosen.rawValue)]
        }
        guard !hops.isEmpty else { return .null }
        return [
            "hops": .array(hops),
            "playerLevel": .init(roll.playerLevel),
            "frozen": .bool(game.worldState.frozenLeveledLevel(of: key) != nil),
            "encounterLevel": .init(roll.encounterLevel),
            "difficulty": .string("\(roll.difficulty)")
        ]
    }

    public func actorValueState(_ text: String, name: String) throws(AgentFailure) -> AgentJSON {
        guard let values = game.actorValues.runtime else {
            throw AgentFailure(.notReady, "actor values are not loaded")
        }
        let reference = try hub.resolveReference(text)
        let holder = try hub.actorValueHolder(for: reference)
        let index = try hub.actorValueIndex(name)
        guard let value = values.value(at: index, on: holder) else {
            throw AgentFailure(.notFound, "\(name) has no value on this actor")
        }
        return [
            "ref": .formID(reference.formID.rawValue),
            "name": .string(name),
            "value": .init(value)
        ]
    }
}
