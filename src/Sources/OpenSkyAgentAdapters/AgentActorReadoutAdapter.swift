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
public protocol AgentActorReadoutHost: AnyObject, SendableMetatype {
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
        CellAndTarget(owner: self).cellState(at: position)
    }

    /// Null only when the view ray met nothing; with no target, only `rayHit`.
    public func targetState() -> AgentJSON {
        CellAndTarget(owner: self).targetState()
    }

    /// The nearest `detailed` actors get a full row and the others a short one, so the
    /// reply stays under the size of one line with a town loaded.
    public func actorsState(radius: Float, detailed: Int) throws(AgentFailure) -> AgentJSON {
        guard let gameSession = game.gameSession else { throw hub.notReady() }
        let origin = gameSession.freeFlyCamera.position
        let near = game.actorWorld.combatActors()
            .map { (simd_distance($0.feet, origin), $0) }
            .filter { $0.0 <= radius }
            .sorted { $0.0 < $1.0 }
        let rows = near.enumerated().map { index, entry in
            var fields = shortRow(entry.1, distance: entry.0)
            if index < detailed {
                fields.merge(detailRow(entry.1, distance: entry.0)) { _, new in new }
            }
            return AgentJSON.object(fields)
        }
        return ["actors": .array(rows), "detailed": .init(min(detailed, rows.count))]
    }

    /// The actor's combat target: `player`, the target's reference, or null.
    private func combatTarget(of key: ReferenceKey) -> AgentJSON {
        guard let target = game.combat.loop?.combatTarget(of: key) else { return .null }
        guard target != .player else { return .string("player") }
        return game.streamer.referenceEntry(key: target).map { .formID($0.formID.rawValue) }
            ?? .null
    }

    private func shortRow(_ actor: CombatActorObservation, distance: Float) -> [String: AgentJSON] {
        let formID = game.streamer.referenceEntry(key: actor.key)?.formID
        return [
            "ref": formID.map { .formID($0.rawValue) } ?? .null,
            "name": .string(game.dialogueWorld.speakerLabel(for: actor.key)),
            "position": .init(actor.feet),
            "distance": .init(distance),
            "dead": .bool(actor.isDead),
            "hostility": .string("\(game.factions.hostility(of: actor.key))"),
            "combat": game.combat.loop?.phase(of: actor.key).map { .string("\($0)") } ?? .null,
            "target": combatTarget(of: actor.key),
            "startedFight": .bool(game.combat.loop?.aggressors.contains(actor.key) == true),
            "aggro": game.combat.loop?.aggroZone(of: actor.key)
                .map { .string($0.rawValue) } ?? .null,
            "weapon": game.combat.loop?.drawState(of: actor.key)
                .map { .string($0.rawValue) } ?? .null,
            "detects": game.perception.runtime
                .map { .string("\($0.state(observer: actor.key, target: .player).state)") }
                ?? .null
        ]
    }

    private func graphState(of key: ReferenceKey) -> AgentJSON {
        let graph: AgentJSON = game.actorGraphs.readout(for: key).map(details.graphState) ?? .null
        guard case var .object(fields) = graph else { return graph }
        let getUp = game.actorGraphs.variable(named: ActorStateGraphNames.getUpType, on: key)
        if case let .int(value) = getUp {
            fields["iGetUpType"] = .init(Int(value))
        }
        return .object(fields)
    }

    private func detailRow(
        _ actor: CombatActorObservation, distance: Float
    ) -> [String: AgentJSON] {
        let base = game.streamer.referenceEntry(key: actor.key)?.placedActor?.base
        return [
            "leveled": details.leveledState(of: actor.key, base: base),
            "height": .init(game.streamer.npcHeightScale?(actor.key) ?? 1),
            "detection": detection(by: actor.key),
            "social": socialState(of: actor.key),
            "eyeTexture": actors.eyeTexture(of: actor.key),
            "severed": actors.severedState(of: actor.key),
            "soundLoops": .array(
                (game.gameSession?.soundDirector?.actorLoopNames(of: actor.key) ?? [])
                    .map(AgentJSON.string)
            ),
            "skinDecals": .array(render.skinDecalBones(of: actor.key).map(AgentJSON.string)),
            "constraints": actors.physicsConstraints(of: actor.key),
            "ragdoll": actors.ragdollBodies(of: actor.key),
            "lagBones": .object(
                (game.actorPlayback(for: actor.key)?.lagBoneOffsets ?? [:])
                    .mapValues(AgentJSON.init)
            ),
            "graph": graphState(of: actor.key),
            "bands": details.bands(of: actor.key, distance: distance)
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

extension AgentActorReadoutAdapter {
    private var details: AgentActorDetails {
        AgentActorDetails(game: game)
    }

    private var render: AgentRenderAdapter {
        AgentRenderAdapter(hub: hub, game: hub.hosts)
    }

    private var actors: AgentActorsAdapter {
        AgentActorsAdapter(hub: hub, game: hub.hosts)
    }
}

/// An actor's behaviour graph and leveled roll, for `AgentActorReadoutAdapter`.
struct AgentActorDetails {
    let game: any AgentActorReadoutHost

    /// The update band at the camera distance, and the band movement and perception use
    /// (docs/engine/update-bands.md).
    func bands(of key: ReferenceKey, distance: Float) -> AgentJSON {
        [
            "distance": .string(UpdateBands.standard.band(atDistance: distance).name),
            "movement": game.streamer.npcMovement.movementBand(of: key)
                .map { .string($0.name) } ?? .null,
            "perception": game.perception.perceptionBand(of: key)
                .map { .string($0.name) } ?? .null
        ]
    }

    func graphState(_ graph: ActorGraphReadout) -> AgentJSON {
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
    func leveledState(of key: ReferenceKey, base: FormID?) -> AgentJSON {
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
}

extension AgentActorReadoutAdapter {
    /// What the actor's last detection check of the player found.
    private func detection(by key: ReferenceKey) -> AgentJSON {
        guard let pair = game.perception.runtime?.state(observer: key, target: .player)
        else { return .null }
        let event = game.perception.runtime?.soundEvent(of: .player)
        return .object([
            "soundEvent": event.map { ["level": .init($0.level), "age": .init($0.age)] } ?? .null,
            "level": .init(pair.level),
            "value": .init(pair.breakdown.value),
            "sound": .init(pair.breakdown.soundFactor),
            "sight": .init(pair.breakdown.visualFactor),
            "lineOfSight": .bool(pair.hasLineOfSight),
            "inViewCone": .bool(pair.isInViewCone)
        ])
    }
}

extension AgentActorReadoutAdapter {
    /// Reads the cell at a place and the player's target.
    struct CellAndTarget {
        let owner: AgentActorReadoutAdapter

        func cellState(at position: SIMD3<Float>) -> AgentJSON {
            let game = owner.game
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

        func targetState() -> AgentJSON {
            let game = owner.game
            let streamer = game.streamer
            let rayHit: AgentJSON = streamer.interactionRayHit.map { hit in
                [
                    "ref": .formID(hit.reference.rawValue),
                    "base": streamer.referenceEntry(formID: hit.reference)?.placedReference.map {
                        AgentJSON.formID($0.base.rawValue)
                    } ?? .null,
                    "distance": .init(hit.distance),
                    "usable": .bool(streamer.residentInteraction(reference: hit.reference) != nil)
                ]
            } ?? .null
            guard let target = streamer.interactionTarget else {
                guard case .object = rayHit else { return .null }
                return ["rayHit": rayHit]
            }
            // The verb the HUD shows, laid on at run time, not the cell build's fallback.
            let interaction = game.inventory.craftingBench.labelled(target.interaction)
            return [
                "ref": .formID(interaction.reference.rawValue),
                "base": .formID(interaction.base.rawValue),
                "name": .string(interaction.name),
                "action": .string(interaction.actionLabel),
                "distance": .init(target.distance),
                "position": .init(interaction.position),
                "theft": .bool(game.inventory.itemPanels.targetOwnership()?.isTheft == true),
                "rayHit": rayHit
            ]
        }
    }
}
