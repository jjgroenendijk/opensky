import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `AgentActorsAdapter` reads from the session.
@MainActor
public protocol AgentActorsHost: AnyObject, SendableMetatype {
    var actorGraphs: any ActorGraphPort { get }
    var actorWorld: any ActorWorldPort { get }
    var beastForms: any BeastFormWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var perks: any PerkPort { get }
    var player: any PlayerPort { get }
    var playerBeastForm: PlayerBeastForm { get }
    var ragdoll: any RagdollPort { get }
    var renderer: (any RendererPort)? { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
struct AgentActorsAdapter {
    let hub: AgentHub
    let game: any AgentActorsHost
}

extension AgentActorsAdapter {
    func setDrunk(_ reference: String, drunk: Bool) throws(AgentFailure) -> AgentJSON {
        let actor = try hub.resolveReference(reference)
        let event = drunk ? ActorGraphNames.drunkStart : ActorGraphNames.drunkStop
        let taken: Bool
        if actor.key == .player {
            guard let locomotion = game.gameSession?.locomotion else { throw hub.notReady() }
            taken = locomotion.raiseGraphEvent(named: event)
        } else {
            guard game.actorGraphs.instance(of: actor.key) != nil else {
                throw AgentFailure(.invalidArgument, "\(reference) runs no behaviour graph")
            }
            taken = game.actorGraphs.raise(event, on: actor.key)
        }
        return [
            "ref": .formID(actor.formID.rawValue), "event": .string(event), "taken": .bool(taken)
        ]
    }

    /// `debug perk`: the grant `Actor.AddPerk` makes, which also gives the perk's abilities.
    func setPlayerPerk(_ editorID: String, owned: Bool) throws(AgentFailure) -> AgentJSON {
        guard
            let runtime = game.perks.runtime,
            let holder = game.actorWorld.actorValueHolder(for: .player)
        else { throw hub.notReady() }
        guard let perk = runtime.perks.perks.first(where: {
            $0.editorID?.lowercased() == editorID.lowercased()
        }) else {
            throw AgentFailure(.notFound, "no perk '\(editorID)'")
        }
        let key = ReferenceKey(resolved: perk.id)
        let changed = owned ? game.perks.add(key, to: holder) : game.perks.remove(key, from: holder)
        return [
            "perk": .string(perk.editorID ?? editorID), "changed": .bool(changed),
            "owned": .bool(game.perks.ownership(of: .player)?.contains(key) ?? false)
        ]
    }

    func forceBeastForm(_ name: String) throws(AgentFailure) -> AgentJSON {
        let forms: [String: PlayerBeastForm] = [
            "none": .none, "werewolf": .werewolf, "vampirelord": .vampireLord
        ]
        guard let form = forms[name] else {
            throw AgentFailure(.invalidArgument, "form must be werewolf, vampirelord, or none")
        }
        guard game.beastForms.force(form) else {
            throw AgentFailure(.notFound, "the \(name) race is not in the load order")
        }
        return ["form": .string(game.playerBeastForm.rawValue)]
    }

    func setEyes(_ reference: String, textureSet: String) throws(AgentFailure) -> AgentJSON {
        let actor = try hub.resolveReference(reference)
        guard let raw = FormID(hexText: textureSet)?.rawValue else {
            throw AgentFailure(.invalidArgument, "set must be a hex FormID")
        }
        if actor.key == .player {
            game.player.eyeTextureSet = FormID(raw)
            return ["ref": .formID(actor.formID.rawValue), "eyeTexture": eyeTexture(of: actor.key)]
        }
        guard let cell = game.streamer.cellLocation(of: actor.key) else {
            throw AgentFailure(.notFound, "\(reference) has no 3D")
        }
        game.worldState.setEyeTexture(FormID(raw), for: actor.key, in: cell)
        return ["ref": .formID(actor.formID.rawValue), "eyeTexture": eyeTexture(of: actor.key)]
    }

    func decapitate(_ reference: String) throws(AgentFailure) -> AgentJSON {
        let actor = try hub.resolveReference(reference)
        guard game.worldState.component(ActorDeathState.self, for: actor.key)?.isDead == true
        else {
            throw AgentFailure(.unsupported, "\(reference) is alive; kill it first")
        }
        guard game.ragdoll.dismember(actor.key) else {
            throw AgentFailure(.failed, "\(reference) has no head to cut, or it is cut already")
        }
        return ["ref": .formID(actor.formID.rawValue), "severed": severedState(of: actor.key)]
    }

    /// The cut of a decapitated actor: the node, and where its head is. Null while whole.
    func severedState(of key: ReferenceKey) -> AgentJSON {
        guard
            let node = game.worldState.component(ActorDeathState.self, for: key)?.severedNode
        else { return .null }
        let head = game.ragdoll.severedHeads[key]
        let formID = game.streamer.referenceEntry(key: key)?.formID
        let drawn = formID.flatMap { game.renderer?.scene.severedHeadPlayback(for: $0) } != nil
        return [
            "node": .string(node),
            "headPosition": head.map { .init($0.body.position) } ?? .null,
            "headResting": .bool(head?.body.isSleeping ?? false),
            "headDrawn": .bool(drawn)
        ]
    }

    func eyeTexture(of key: ReferenceKey) -> AgentJSON {
        if key == .player {
            return game.player.eyeTextureSet.map { .formID($0.rawValue) } ?? .null
        }
        return game.worldState.component(ActorPresentationState.self, for: key)?.eyeTextureSet
            .map { .formID($0.rawValue) } ?? .null
    }

    /// `debug link`: what `Game.AddHavokBallAndSocketConstraint` does, through its hook.
    func setRagdollLink(
        _ link: AgentRagdollLink,
        linked: Bool
    ) throws(AgentFailure) -> AgentJSON {
        guard let hooks = game.scripts.bridge?.gameNatives else { throw hub.notReady() }
        let first = try PapyrusConstraintEnd(
            reference: hub.resolveReference(link.reference).key, node: link.node
        )
        let second = try PapyrusConstraintEnd(
            reference: hub.resolveReference(link.other).key, node: link.otherNode
        )
        guard linked else {
            let removed = hooks.removeConstraints?(first, second) ?? false
            return [
                "changed": .bool(removed),
                "constraints": physicsConstraints(of: first.reference)
            ]
        }
        let answer = Self.linkAnswer(hooks.addBallAndSocket?(first, second))
        return ["changed": answer, "constraints": physicsConstraints(of: first.reference)]
    }

    private static func linkAnswer(_ result: PapyrusNativeResult?) -> AgentJSON {
        switch result {
        case let .returned(.boolean(added)): .bool(added)
        case .suspended: .string("waiting for the model")
        default: .bool(false)
        }
    }

    /// The script links and pins that hold `key`'s bodies.
    func physicsConstraints(of key: ReferenceKey) -> AgentJSON {
        let world = game.ragdoll.runtime?.world
        let links = (world?.links ?? []).filter {
            $0.first.reference == key || $0.second.reference == key
        }.map { "\(line($0.first)) <-> \(line($0.second))" }
        let pins = ((world?.pins ?? []) + (game.streamer.dynamicBodies.pins))
            .filter { $0.end.reference == key || $0.partner.reference == key }
            .map { "\(line($0.end)) pinned to \(line($0.partner)) at \($0.point)" }
        return .array((links + pins).map(AgentJSON.string))
    }

    private func line(_ end: PhysicsLinkEnd) -> String {
        "\(end.reference) \(end.node)"
    }
}
