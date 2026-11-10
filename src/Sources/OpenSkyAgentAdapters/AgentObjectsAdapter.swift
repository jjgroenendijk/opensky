import Foundation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AgentObjectsAdapter` reads from the session.
@MainActor
public protocol AgentObjectsHost: AnyObject {
    var effectGraphs: any EffectGraphPort { get }
    var effectModelPoser: any EffectModelPoserPort { get }
    var factions: any FactionPort { get }
    var followerCommandWorld: any FollowerCommandWorldPort { get }
    var followerCommands: any FollowerCommandPort { get }
    var nodeControllers: any NodeControllerPort { get }
    var objectAnimationWorld: any ObjectAnimationWorldPort { get }
    var scenes: any ScenePort { get }
    var scripts: any ScriptPort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentObjectsAdapter {
    public let hub: AgentHub
    public let game: any AgentObjectsHost
}

extension AgentObjectsAdapter {
    func favorState() -> AgentJSON {
        let commands = game.followerCommands
        var json: [String: AgentJSON] = [
            "phase": .string(Self.phaseName(commands.phase)),
            "follower": commands.phase.follower.flatMap(hub.behaviour.formID) ?? .null,
            "lastDecision": commands.lastDecision.map(decisionJSON) ?? .null,
            "lastOutcome": commands.lastOutcome.map { .string($0.rawValue) } ?? .null,
            "pickDistance": .init(commands.settings.pickDistance)
        ]
        switch commands.phase {
        case let .walking(_, task):
            json["task"] = taskJSON(task)
        case let .waiting(_, left):
            json["waitLeft"] = .init(left)
        case .idle, .choosing:
            break
        }
        return .object(json)
    }

    private func commandFollower(
        _ reference: String, target: String?, exit: Bool
    ) throws(AgentFailure) -> AgentJSON {
        let follower = try hub.resolveReference(reference).key
        let commands = game.followerCommands
        if exit {
            guard commands.phase.follower == follower, commands.cancel() else {
                throw AgentFailure(.invalidArgument, "\(reference) is not in command mode")
            }
            return favorState()
        }
        if commands.phase.follower != follower || !commands.isChoosing {
            game.followerCommandWorld.enterCommandMode(follower)
        }
        if let target {
            try commands.command(commandTarget(target))
        }
        return favorState()
    }

    public func followerDebug(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .favor(reference, target, exit):
            try commandFollower(reference, target: target, exit: exit)
        case let .teammate(reference, on):
            try setTeammate(reference, on: on)
        case let .relationship(reference, rank):
            try setRelationship(reference, rank: Int8(rank))
        default:
            throw AgentFailure(.invalidArgument, "not a follower command")
        }
    }

    private func setTeammate(_ reference: String, on: Bool) throws(AgentFailure) -> AgentJSON {
        let resolved = try hub.resolveReference(reference)
        guard let bridge = game.scripts.bridge else { throw hub.notReady() }
        bridge.updateScriptedState(of: resolved.key) {
            $0.setFlag(ScriptedStateName.playerTeammate, on)
        }
        let flag = bridge.scriptedState(of: resolved.key).flag(ScriptedStateName.playerTeammate)
        return ["ref": .string(reference), "teammate": .bool(flag == true)]
    }

    /// The reply shows `firstFriendRank`, which fixes the item allowance of a friend.
    private func setRelationship(
        _ reference: String,
        rank: Int8
    ) throws(AgentFailure) -> AgentJSON {
        let resolved = try hub.resolveReference(reference)
        guard let relationships = game.factions.relationships else { throw hub.notReady() }
        relationships.setRank(rank, of: resolved.key, toward: .player, cells: (nil, nil))
        let state = relationships.state(of: .player)
        return [
            "ref": .string(reference),
            "rank": state.rank(toward: resolved.key).map { .init(Int($0)) } ?? .null,
            "firstFriendRank": state.firstFriendRank(toward: resolved.key)
                .map { .init(Int($0)) } ?? .null
        ]
    }

    /// A reference, or `x,y,z` for a spot on the ground.
    private func commandTarget(_ text: String) throws(AgentFailure) -> FollowerCommandTarget? {
        if let point = AgentArguments.point(fromText: text) {
            return FollowerCommandTarget(key: nil, kind: .ground, position: point)
        }
        return try game.followerCommandWorld.commandTarget(hub.resolveReference(text).key)
    }

    private static func phaseName(_ phase: FollowerCommandPhase) -> String {
        switch phase {
        case .idle: "idle"
        case .choosing: "choosing"
        case .walking: "walking"
        case .waiting: "waiting"
        }
    }

    private func decisionJSON(_ decision: FollowerCommandDecision) -> AgentJSON {
        var json: [String: AgentJSON] = ["line": .string(decision.line.description)]
        switch decision {
        case let .agree(task): json["task"] = taskJSON(task)
        case let .refuse(reason): json["refusal"] = .string(reason.rawValue)
        case let .moralRefusal(crime): json["crime"] = .string(crime.rawValue)
        }
        return .object(json)
    }

    private func taskJSON(_ task: FollowerCommandTask) -> AgentJSON {
        [
            "action": .string(task.action.rawValue),
            "target": task.target.key.flatMap(hub.behaviour.formID) ?? .null,
            "position": .init(task.target.position),
            "kind": .string(task.target.kind.rawValue),
            "unlocks": .bool(task.unlocks),
            "crime": task.crime.map { .string($0.rawValue) } ?? .null
        ]
    }

    public func scenesState() -> AgentJSON {
        let snapshot = game.scenes.sceneSnapshot
        let playing = snapshot.playing.map { row -> AgentJSON in
            [
                "id": .string(row.editorID),
                "phase": .init(row.phase),
                "phaseCount": .init(row.phaseCount),
                "phaseName": row.phaseName.map(AgentJSON.string) ?? .null,
                "running": .array(row.runningActions.map { .init(Int($0)) })
            ]
        }
        return [
            "playing": .array(playing),
            "trace": .array(snapshot.trace.map(AgentJSON.string)),
            "lines": .array(snapshot.lines.map(AgentJSON.string))
        ]
    }

    /// The answer to `openskycli game state scripts`: queue, waits, the newest events,
    /// the newest fault, and the natives that are missing most.
    func scriptsState(reference: String?) throws(AgentFailure) -> AgentJSON {
        let snapshot = game.scripts.scriptsSnapshot
        let owner = try reference.map { text throws(AgentFailure) in try scriptOwner(text) }
        return [
            "on": owner.map(instancesState(on:)) ?? .null,
            "waits": owner.map(waitsState(on:)) ?? .null,
            "instances": .init(snapshot.instanceCount),
            "pendingEvents": .init(snapshot.pendingEventCount),
            "pendingWaits": .init(snapshot.pendingWaitCount),
            "recentEvents": .array(snapshot.recentEvents.map(AgentJSON.string)),
            "lastFault": snapshot.lastFault.map(AgentJSON.string) ?? .null,
            "unimplemented": .array(snapshot.topUnimplementedNatives.map {
                ["name": .string($0.name), "count": .init($0.count)]
            })
        ]
    }

    /// A quest editor ID, else a reference as `resolveReference` reads it.
    private func scriptOwner(_ text: String) throws(AgentFailure) -> ReferenceKey {
        if let quest = game.scripts.bridge?.questKey(editorID: text) {
            return quest
        }
        return try hub.resolveReference(text).key
    }

    /// The calls the reference's scripts wait in, such as `Utility.Wait` or an
    /// animation event, so a stalled script shows where it stopped.
    private func waitsState(on key: ReferenceKey) -> AgentJSON {
        guard let world = game.scripts.runtime else {
            return .array([])
        }
        return .array(world.waits(on: key).map { wait in
            [
                "script": .string(wait.script),
                "native": .string(wait.native),
                "request": .string(wait.request)
            ]
        })
    }

    private func instancesState(on key: ReferenceKey) -> AgentJSON {
        guard let world = game.scripts.runtime else { return .array([]) }
        return .array(world.instances(on: key).map { instance in
            [
                "script": .string(instance.script),
                "state": .string(instance.state),
                "variables": .array(instance.variables.map(AgentJSON.string))
            ]
        })
    }

    /// Every running graph, or one with its bone positions in the object's own space.
    func objectsState(reference: String?) throws(AgentFailure) -> AgentJSON {
        let objects = game.objectAnimationWorld.objects
        guard let reference else {
            return ["objects": .array(objects.rows.map(Self.json))]
        }
        let target = try hub.resolveReference(reference)
        guard let row = objects.rows.first(where: { $0.reference == target.formID.rawValue }) else {
            throw AgentFailure(.notFound, "that reference runs no object graph")
        }
        var fields = Self.fields(row)
        let bones = objects.boneMatrices(of: row.reference) ?? []
        fields["bones"] = .array(bones.map(Self.bone))
        return .object(fields)
    }

    /// A swing turns a bone about its own origin, so the rotation shows it.
    static func bone(_ matrix: simd_float4x4) -> AgentJSON {
        let rotation = simd_quatf(simd_float3x3(
            SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        ))
        return [
            "position": .init(SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)),
            "rotationDegrees": .init(MatrixMath.degrees(fromRadians: rotation.angle))
        ]
    }

    private static func json(_ row: ObjectAnimationRow) -> AgentJSON {
        .object(fields(row))
    }

    private static func fields(_ row: ObjectAnimationRow) -> [String: AgentJSON] {
        [
            "ref": .formID(row.reference),
            "project": .string(row.project),
            "state": .init(row.activeState),
            "states": .array(row.activeStates.map { .string($0) }),
            "waitingForClip": .bool(row.isWaitingForClip),
            "events": .array(row.events.map { .string($0) })
        ]
    }

    /// Every running effect graph, or those on one actor (docs/engine/effect-graphs.md),
    /// and every effect model drawn as its own posed copy.
    public func effectsState(reference: String?) throws(AgentFailure) -> AgentJSON {
        var rows = game.effectGraphs.rows
        if let reference {
            let target = try hub.resolveReference(reference)
            rows = rows.filter { $0.actor == target.key }
        }
        let posed = game.effectModelPoser.rows.map { row -> AgentJSON in
            [
                "effect": .init(row.effectID),
                "model": .string(row.modelPath),
                "bones": .array(row.bones.map { .string($0) })
            ]
        }
        return ["posed": .array(posed), "effects": .array(rows.map(Self.subGraphFields))]
    }

    private static func subGraphFields(_ row: EffectGraphRow) -> AgentJSON {
        var fields: [String: AgentJSON] = [
            "actor": .init(row.actor.map { "\($0)" }),
            "name": .string(row.name),
            "project": .string(row.project),
            "state": .init(row.activeState),
            "lastEvent": .init(row.lastEvent),
            "eventsTaken": .init(row.takenCount),
            "sequences": .array(row.sequences.map(AgentJSON.string))
        ]
        switch row.id {
        case let .effect(id):
            fields["effect"] = .init(id)
        case let .armorAddon(_, armature):
            fields["armorAddon"] = .formID(armature)
        }
        if case let .point(position) = row.anchor {
            fields["point"] = .array([position.x, position.y, position.z].map { AgentJSON($0) })
        }
        return .object(fields)
    }

    /// Every mesh that plays node controllers, or one mesh's driven nodes.
    func nodesState(reference: String?) throws(AgentFailure) -> AgentJSON {
        let nodes = game.nodeControllers
        guard let reference else {
            return ["nodes": .array(nodes.references.map { ["ref": .formID($0)] })]
        }
        let target = try hub.resolveReference(reference)
        guard let rows = nodes.nodes(of: target.formID.rawValue) else {
            throw AgentFailure(.notFound, "that reference plays no node controllers")
        }
        return ["ref": .formID(target.formID.rawValue), "nodes": .array(rows.map { row in
            let axis = row.rotation.act(SIMD3<Float>(1, 0, 0))
            return [
                "name": .string(row.name),
                "position": .init(row.translation),
                "forward": .init(axis),
                "rotationDegrees": .init(MatrixMath.degrees(fromRadians: row.rotation.angle)),
                "controllers": .array(row.controllers.map { .string($0) }),
                "active": .bool(row.isActive),
                "frozen": .bool(row.isFrozen)
            ]
        })]
    }

    /// Answers whether a sub-graph took the change, with the actor's sub-graphs after it.
    public func driveSubGraphs(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        let taken: Bool
        let reference: String
        switch command {
        case let .subGraphEvent(ref, event):
            reference = ref
            taken = try game.effectGraphs.deliver(event, from: hub.resolveReference(ref).key)
        case let .subGraphVariable(ref, name, value):
            reference = ref
            taken = try game.effectGraphs.setSubGraphVariable(
                value, named: name, on: hub.resolveReference(ref).key
            )
        default:
            throw AgentFailure(.invalidArgument, "not a sub-graph command")
        }
        return try ["taken": .bool(taken), "subGraphs": effectsState(reference: reference)]
    }
}
