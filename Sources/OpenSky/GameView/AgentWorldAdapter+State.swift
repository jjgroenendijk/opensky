// Read-only answers for `openskycli game state ...`. References are "player",
// "target", or a hex FormID of a resident reference.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAgentControl
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombat
import OpenSkyDiagnostics
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

struct AgentReference {
    let key: ReferenceKey
    let formID: FormID
}

extension AgentWorldAdapter {
    func query(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON {
        switch query {
        case .player: try playerState()
        case .target: targetState()
        case let .actors(radius): try actorsState(radius: radius)
        case .menu: menuState
        case let .quest(editorID): try questState(editorID)
        case .scenes: scenesState()
        case .scripts, .packages, .furniture, .objects, .effects, .nodes, .changes, .flight,
             .mount:
            try inspection(query)
        case let .actorValue(reference, name): try actorValueState(reference, name: name)
        case let .global(editorID): try globalState(editorID)
        case .time: timeState()
        case .frame: frameState()
        case .view: try viewState()
        }
    }

    /// The reads that look inside the scripts, the packages, and the seats.
    private func inspection(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON {
        switch query {
        case let .scripts(reference): try scriptsState(reference: reference)
        case let .packages(reference): try packagesState(reference: reference)
        case let .furniture(reference): try furnitureState(reference: reference)
        case let .objects(reference): try objectsState(reference: reference)
        case let .effects(reference): try effectsState(reference: reference)
        case let .nodes(reference): try nodesState(reference: reference)
        case let .changes(limit): changesState(limit: limit)
        case let .flight(reference): try flightState(reference: reference)
        case .mount: mountState()
        default: throw AgentFailure(.invalidArgument, "not an inspection query")
        }
    }

    func resolveReference(_ text: String) throws(AgentFailure) -> AgentReference {
        switch text.lowercased() {
        case "player":
            return AgentReference(key: .player, formID: FormID(0x14))
        case "target":
            guard let target = game.streamer?.interactionTarget else {
                throw AgentFailure(.notFound, "nothing is under the crosshair")
            }
            return try resolveFormID(target.interaction.reference)
        default:
            let digits = text.hasPrefix("0x") || text
                .hasPrefix("0X") ? String(text.dropFirst(2)) : text
            guard let raw = UInt32(digits, radix: 16) else {
                throw AgentFailure(.invalidArgument, "ref must be player, target, or a hex FormID")
            }
            return try resolveFormID(FormID(raw))
        }
    }

    private func resolveFormID(_ formID: FormID) throws(AgentFailure) -> AgentReference {
        guard let entry = game.streamer?.referenceEntry(formID: formID) else {
            throw AgentFailure(
                .notFound,
                "no loaded reference \(AgentJSON.formID(formID.rawValue))"
            )
        }
        return AgentReference(key: entry.key, formID: formID)
    }

    func actorValueHolder(for reference: AgentReference) throws(AgentFailure) -> ActorValueHolder {
        guard let holder = game.actorWorld.actorValueHolder(for: reference.key) else {
            throw AgentFailure(
                .notFound,
                "\(AgentJSON.formID(reference.formID.rawValue)) is not a loaded actor"
            )
        }
        return holder
    }

    func actorValueIndex(_ name: String) throws(AgentFailure) -> Int32 {
        guard let index = ActorValueIdentity.index(named: name) else {
            throw AgentFailure(.invalidArgument, "unknown actor value '\(name)'")
        }
        return index
    }

    private func playerState() throws(AgentFailure) -> AgentJSON {
        guard let gameSession = game.gameSession else { throw notReady() }
        let camera = gameSession.freeFlyCamera
        var result: [String: AgentJSON] = [
            "position": .init(camera.position),
            "yaw": .init(remainder(camera.yaw * 180 / .pi, 360)),
            "pitch": .init(camera.pitch * 180 / .pi),
            "movementMode": .string(String(describing: gameSession.movementMode)),
            "cell": cellState(at: camera.position),
            "worldspace": game.streamer.map { .string($0.worldspaceEditorID) } ?? .null,
            "weather": gameSession.weather?.currentWeatherEditorID.map(AgentJSON.string) ?? .null,
            "bodyFailure": .init(game.player.failureReason)
        ]
        if let values = game.actorValues.runtime {
            let current = values.current(of: .player)
            let maximum = values.maximums(of: .player)
            result["level"] = .init(values.baselines.playerLevel.level)
            result["health"] = ["current": .init(current.health), "max": .init(maximum.health)]
            result["magicka"] = ["current": .init(current.magicka), "max": .init(maximum.magicka)]
            result["stamina"] = ["current": .init(current.stamina), "max": .init(maximum.stamina)]
        }
        // Abilities such as Rested show here; the game lists them in the magic menu.
        result["spells"] = .array(game.magic.playerKnownSpells().map { spell in
            .string(spell.editorID ?? "\(spell.id)")
        })
        result["firstPerson"] = firstPersonState(gameSession: gameSession)
        result["bowZoom"] = [
            "zoomed": .bool(gameSession.bowZoomViewShare < 1),
            "viewShare": .init(gameSession.bowZoomViewShare),
            "timeScale": .init(gameSession.bowZoomTimeScale),
            "fovYDegrees": .init(gameSession.viewFOVYRadians * 180 / .pi)
        ]
        let status = gameSession.locomotion.status
        result["graph"] = [
            "attached": .bool(status.graphAvailable),
            "raisedEvents": .array(status.raisedEvents.map(AgentJSON.string)),
            "missingEvents": .array(status.missingEvents.map(AgentJSON.string)),
            "recentEvents": .array(status.recentGraphEvents.map(AgentJSON.string)),
            "activeStates": .array((gameSession.locomotion.graph?.activeStates ?? []).map {
                .string("\($0.machineName ?? "?") / \($0.stateName ?? "?")")
            }),
            "drunk": .bool(gameSession.locomotion.actorState.isDrunk),
            "iState": gameSession.locomotion.graph?.variable(named: ActorGraphNames.state)
                .map { .init($0.intValue) } ?? .null
        ]
        return .object(result)
    }

    private func firstPersonState(gameSession: GameSession) -> AgentJSON {
        let snapshot = game.player.firstPersonSnapshot
        let rig = gameSession.playerFirstPersonRig
        return [
            "graphAttached": .bool(snapshot.graphAttached),
            "rigAttached": .bool(snapshot.rigAttached),
            "drawn": .bool(snapshot.active),
            "failure": .init(snapshot.failureReason),
            "armModels": .init(snapshot.armModelCount),
            "bonesPosed": .init(rig?.animation.lastUpdatedBoneCount ?? 0),
            "graphUpdates": .init(snapshot.graphUpdates),
            "missingEvents": .array(snapshot.missingEvents.map(AgentJSON.string)),
            "missingVariables": .array(snapshot.missingVariables.map(AgentJSON.string))
        ]
    }

    private func cellState(at position: SIMD3<Float>) -> AgentJSON {
        guard let streamer = game.streamer else { return .null }
        if let interior = streamer.interiorScene {
            return ["interior": true, "name": .string(interior.summary.cellName)]
        }
        let grid = CellCoordinate(containing: position)
        return [
            "interior": false, "x": .init(Int(grid.x)), "y": .init(Int(grid.y)),
            "name": .init(streamer.composition.cells[grid]?.summary.cellName)
        ]
    }

    private func targetState() -> AgentJSON {
        guard let target = game.streamer?.interactionTarget else { return .null }
        let interaction = target.interaction
        return [
            "ref": .formID(interaction.reference.rawValue),
            "base": .formID(interaction.base.rawValue),
            "name": .string(interaction.name),
            "action": .string(interaction.actionLabel),
            "distance": .init(target.distance),
            "position": .init(interaction.position)
        ]
    }

    private func actorsState(radius: Float) throws(AgentFailure) -> AgentJSON {
        guard let gameSession = game.gameSession else { throw notReady() }
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
        let entry = game.streamer?.referenceEntry(key: actor.key)
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
        guard let chain = try? templates.rolling(roll).resolve(base: base).chain else {
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

    private func questState(_ editorID: String) throws(AgentFailure) -> AgentJSON {
        guard let quests = game.journalMenu.questRuntime else {
            throw AgentFailure(.notReady, "no quest data is loaded")
        }
        guard let state = try? quests.state(editorID: editorID) else {
            throw AgentFailure(.notFound, "no quest '\(editorID)'")
        }
        return [
            "id": .string(editorID),
            "stage": state.stagesReached.last.map { .init(Int($0)) } ?? .null,
            "stagesDone": .array(state.stagesReached.map { .init(Int($0)) }),
            "running": .bool(state.isRunning),
            "completed": .bool(state.isCompleted),
            "aliases": aliasFills(editorID, in: quests)
        ]
    }

    /// Each reference alias by name, with the reference that fills it or null.
    private func aliasFills(_ editorID: String, in quests: QuestRuntime) -> AgentJSON {
        guard let quest = quests.quests.quest(editorID: editorID) else { return .null }
        let table = try? quests.aliasState(of: quest.formID)
        var fills: [String: AgentJSON] = [:]
        for alias in quest.aliases where alias.category == .reference {
            let name = alias.name ?? String(alias.id)
            fills[name] = table?.reference(forAlias: alias.id).map { .string("\($0)") } ?? .null
        }
        return .object(fills)
    }

    private func actorValueState(_ text: String, name: String) throws(AgentFailure) -> AgentJSON {
        guard let values = game.actorValues.runtime else {
            throw AgentFailure(.notReady, "actor values are not loaded")
        }
        let reference = try resolveReference(text)
        let holder = try actorValueHolder(for: reference)
        let index = try actorValueIndex(name)
        guard let value = values.value(at: index, on: holder) else {
            throw AgentFailure(.notFound, "\(name) has no value on this actor")
        }
        return [
            "ref": .formID(reference.formID.rawValue),
            "name": .string(name),
            "value": .init(value)
        ]
    }

    private func globalState(_ editorID: String) throws(AgentFailure) -> AgentJSON {
        guard let global = game.runtimeState.runtimeStateGlobal(editorID: editorID) else {
            throw AgentFailure(.notFound, "no global '\(editorID)'")
        }
        return [
            "id": .string(global.editorID), "value": .init(global.currentValue),
            "default": .init(global.defaultValue), "overridden": .bool(global.isOverridden)
        ]
    }

    private func timeState() -> AgentJSON {
        let clock = game.runtimeState.runtimeStateClock
        return [
            "hour": .init(clock.hourOfDay), "day": .init(clock.day),
            "month": .string(clock.monthName),
            "year": .init(clock.year), "daysPassed": .init(clock.daysPassed),
            "timescale": .init(clock.timescale), "simulation": agentTimeline.json
        ]
    }

    private func frameState() -> AgentJSON {
        let stats = game.renderControls.frameStatsSnapshot
        return [
            "timeline": agentTimeline.json,
            "fps": .number(stats.fps), "frameMS": .number(stats.frameMS),
            "maxFrameMS": .number(stats.maxFrameMS),
            "gpuMS": stats.gpuMS.map(AgentJSON.number) ?? .null,
            "memoryMB": MemoryFootprint.physFootprintMB().map(AgentJSON.number) ?? .null,
            "interpolation": interpolationState(),
            "terrainLOD": terrainLODState(),
            "screenFade": screenFadeState()
        ]
    }

    /// The `Game.FadeOutGame` fader: its colour, how much it covers, and whether it moves.
    func screenFadeState() -> AgentJSON {
        guard let fade = game.gameSession?.imageSpace.screenFade else { return .null }
        return [
            "colour": .string(fade.colour == .zero ? "black" : "white"),
            "cover": .init(fade.cover), "running": .bool(fade.isRunning)
        ]
    }

    private func terrainLODState() -> AgentJSON {
        guard let curve = game.renderControls.terrainLODBrightness else { return .null }
        return [
            "brighteningGain": .init(curve.gain),
            "brighteningExponent": .init(curve.exponent),
            "darkeningFactor": .init(curve.typicalFactor)
        ]
    }

    private func interpolationState() -> AgentJSON {
        guard let status = game.renderControls.renderPerformanceSnapshot?.frameInterpolation
        else { return .null }
        return [
            "enabled": .bool(status.enabled), "running": .bool(status.isRunning),
            "shownFPS": .number(status.shownFPS),
            "builtFrames": .init(status.interpolatedFrames),
            "presentLatencyMS": status.presentLatencyMS.map(AgentJSON.number) ?? .null,
            "frameGapMS": status.pacing.map { .number($0.averageGapMS) } ?? .null,
            "longestFrameGapMS": status.pacing.map { .number($0.longestGapMS) } ?? .null,
            "hitches": status.pacing.map { .init($0.hitches) } ?? .null
        ]
    }
}
