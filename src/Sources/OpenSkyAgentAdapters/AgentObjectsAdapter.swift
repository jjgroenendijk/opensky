import Foundation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyConditions
public import OpenSkyCrimeInterface
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
public import OpenSkyPlayer
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
public protocol AgentObjectsHost: AnyObject, SendableMetatype {
    var clothReadout: ClothReadout { get }
    var crimeAlarmReadout: CrimeAlarmReadout { get }
    var effectGraphs: any EffectGraphPort { get }
    var effectModelPoser: any EffectModelPoserPort { get }
    var factions: any FactionPort { get }
    var followerCommandWorld: any FollowerCommandWorldPort { get }
    var followerCommands: any FollowerCommandPort { get }
    var nodeControllers: any NodeControllerPort { get }
    var objectAnimationWorld: any ObjectAnimationWorldPort { get }
    var scenes: any ScenePort { get }
    var scripts: any ScriptPort { get }
    var storyManager: any StoryManagerPort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentObjectsAdapter {
    public let hub: AgentHub
    public let game: any AgentObjectsHost
}

extension AgentObjectsAdapter {
    func clothState() -> AgentJSON {
        let readout = game.clothReadout
        return [
            "enabled": .bool(readout.isEnabled),
            "stepped": .init(readout.steppedCount),
            "capes": .array(readout.capes.map { cape in
                [
                    "actor": .formID(cape.actor.rawValue), "bone": .string(cape.bone),
                    "stepped": .bool(cape.stepped),
                    "miss": cape.miss.map { .string($0.rawValue) } ?? .null
                ]
            })
        ]
    }

    func favorState() -> AgentJSON {
        followers.favorState()
    }

    public func followerDebug(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        try followers.followerDebug(command)
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

    /// The answer to `openskycli game state story`: the count of each event code fired
    /// this session, and the newest events with their data, oldest first.
    public func storyState() -> AgentJSON {
        let story = game.storyManager
        var fired: [String: AgentJSON] = [:]
        for (code, count) in story.firedCounts {
            fired[code.description] = .init(count)
        }
        let recent = story.recentEvents.map { event -> AgentJSON in
            func key(_ key: ReferenceKey?) -> AgentJSON {
                key.map { .string($0.description) } ?? .null
            }
            return [
                "event": .string(event.event.description),
                "r1": key(event.actor1),
                "r2": key(event.actor2),
                "f1": event.form.map { .formID($0.rawValue) } ?? .null,
                "l1": event.location1.map { .string("\($0)") } ?? .null,
                "q1": event.quest.map { .formID($0.rawValue) } ?? .null,
                "v1": .init(event.value1),
                "v2": .init(event.value2)
            ]
        }
        let rejected = story.recentRejections.map { rejection -> AgentJSON in
            [
                "event": .string(rejection.event.description),
                "quest": .formID(rejection.quest.rawValue),
                "reason": .string(String(describing: rejection.reason))
            ]
        }
        return ["fired": .object(fired), "recent": .array(recent), "rejected": .array(rejected)]
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
            "noneReceiverCalls": .init(snapshot.noneReceiverCalls),
            "translations": translationsJSON(),
            "unimplemented": .array(snapshot.topUnimplementedNatives.map {
                ["name": .string($0.name), "count": .init($0.count)]
            })
        ]
    }

    /// Starts a `TranslateTo` move that keeps the reference's rotation.
    func translate(
        _ reference: String, to position: SIMD3<Float>, speed: Float
    ) throws(AgentFailure) -> AgentJSON {
        let key = try hub.resolveReference(reference).key
        guard let bridge = game.scripts.bridge else {
            throw AgentFailure(.notReady, "no scripts are loaded")
        }
        let started = bridge.translate(key, to: position, speed: speed)
        return ["started": .bool(started), "translations": translationsJSON()]
    }

    /// Every running or waiting scripted move, in key order.
    private func translationsJSON() -> AgentJSON {
        let moves = game.scripts.bridge?.savedTranslations() ?? [:]
        return .array(moves.keys.sorted().compactMap { key in
            moves[key].map { move in
                [
                    "ref": .string(key.description), "position": .init(move.position),
                    "target": .init(move.targetPosition), "speed": .init(move.speed)
                ]
            }
        })
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

extension AgentObjectsAdapter {
    private var followers: AgentFollowerCommands {
        AgentFollowerCommands(hub: hub, game: game)
    }
}

/// The follower command mode, teammates, and relationships, for `AgentObjectsAdapter`.
struct AgentFollowerCommands {
    let hub: AgentHub
    let game: any AgentObjectsHost

    func favorState() -> AgentJSON {
        let commands = game.followerCommands
        var json: [String: AgentJSON] = [
            "phase": .string(Self.phaseName(commands.phase)),
            "follower": commands.phase.follower.flatMap(hub.formID) ?? .null,
            "lastDecision": commands.lastDecision.map(decisionJSON) ?? .null,
            "lastOutcome": commands.lastOutcome.map { .string($0.rawValue) } ?? .null,
            "pickDistance": .init(commands.settings.pickDistance),
            "pendingWalk": commands.pendingWalk.map { .init($0.asked) } ?? .null
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

    func followerDebug(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
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
            "target": task.target.key.flatMap(hub.formID) ?? .null,
            "position": .init(task.target.position),
            "kind": .string(task.target.kind.rawValue),
            "unlocks": .bool(task.unlocks),
            "crime": task.crime.map { .string($0.rawValue) } ?? .null
        ]
    }
}

/// The crime alarm: who saw what, who fights, and any jail stay.
@MainActor
struct AgentAlarmReadout {
    let hub: AgentHub
    let game: any AgentObjectsHost

    func alarmState() -> AgentJSON {
        let readout = game.crimeAlarmReadout
        return [
            "witnesses": .array(readout.witnesses.map { witness in
                [
                    "ref": alarmRef(witness.key), "role": .string(witness.role),
                    "criminal": witness.criminal.map(alarmRef) ?? .null,
                    "crimes": .init(witness.crimes)
                ]
            }),
            "fighters": .array(readout.fighters.map { fighter in
                [
                    "ref": alarmRef(fighter.witness),
                    "fights": .array(fighter.criminals.map(alarmRef))
                ]
            }),
            "angry": .array(readout.angry.map(alarmRef)),
            "theftMarkDay": readout.theftMarkDay.map { .init($0) } ?? .null,
            "openCrimes": .init(readout.openCrimes),
            "last": .string(readout.last),
            "jail": readout.jail.map { stay in
                [
                    "sentenceDays": .init(stay.sentenceDays),
                    "marker": alarmRef(stay.exteriorMarker),
                    "inCell": .bool(stay.cell != nil)
                ]
            } ?? .null,
            "jailFollowers": .array(readout.jailFollowers.map(alarmRef)),
            "trespass": [
                "trespassing": .bool(readout.trespass.isTrespassing),
                "warned": .bool(readout.trespass.isWarnedToLeave),
                "cellOpened": .bool(readout.trespass.isCellOpened)
            ]
        ]
    }

    func alarmRef(_ key: ReferenceKey) -> AgentJSON {
        key == .player ? .string("player") : hub.formID(of: key) ?? .string("\(key)")
    }
}
