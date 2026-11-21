import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogue
public import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyQuests
public import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `StorySocialSearchAdapter` reads from the session.
@MainActor
public protocol StorySocialSearchHost: AnyObject, SendableMetatype {
    var actorWorld: any ActorWorldPort { get }
    var aiWorld: any AIWorldPort { get }
    var combat: any CombatPort { get }
    var dialogue: any DialoguePort { get }
    var furniture: any FurniturePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var packages: any PackagePort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
    var scenes: any ScenePort { get }
    var dialogueWorld: any DialogueWorldPort { get }
}

/// Part of `StoryWorldAdapter`, over its own narrow host.
public struct StorySocialSearchAdapter {
    public let game: any StorySocialSearchHost
    public let sceneCast: StorySceneCastAdapter
}

extension StorySocialSearchAdapter {
    var questReferences: QuestReferences {
        QuestReferences(game: game)
    }

    /// Nil while no cell is loaded.
    public func questReferenceSearch() -> QuestReferenceSearch? {
        questReferences.questReferenceSearch()
    }

    public func createQuestReference(_ base: FormID, at anchor: ReferenceKey) -> ReferenceKey? {
        questReferences.createQuestReference(base, at: anchor)
    }

    /// The quest reference search and spawn, which read the streamer and the world state.
    struct QuestReferences {
        let game: any StorySocialSearchHost
    }
}

extension StorySocialSearchAdapter.QuestReferences {
    func questReferenceSearch() -> QuestReferenceSearch? {
        let streamer = game.streamer
        let references = streamer.residentReferenceIndex()
        let store = game.worldState
        let enable = EnableParentResolver(
            delta: { store.delta(for: $0) },
            parent: { [weak streamer] in streamer?.referenceEntry(formID: $0) }
        )
        var context = game.dialogueWorld.conditionContext()
        context.references = references
        let feet = game.gameSession.map { gameSession in
            gameSession.movementMode.isPlayerControlled
                ? gameSession.walkController.feetPosition : gameSession.freeFlyCamera.position
        }
        return QuestReferenceSearch(
            references: references,
            origin: feet,
            context: context.using(ConditionFunctionRegistry.standard),
            dead: Set(game.actorWorld.combatActors().filter(\.isDead).map(\.key))
        ) { key in
            references[key].map { !enable.isEnabled($0) } ?? false
        }
    }

    /// A new reference of `base` where `anchor` stands, loaded or not. It is a spawn, so
    /// the save keeps it and a cell build places it like a dropped item or an actor.
    func createQuestReference(_ base: FormID, at anchor: ReferenceKey) -> ReferenceKey? {
        guard
            let placement = game.scripts.bridge?.placement(of: anchor),
            let location = placement.location
        else { return nil }
        let spawn = ReferenceSpawnState(
            base: base, location: location, placement: placement.state.transform.placement
        )
        let key = game.worldState.allocateGeneratedKey()
        game.worldState.set(spawn, for: key, in: location)
        return key
    }
}

extension StorySocialSearchAdapter {
    public func socialFrame() -> SocialFrame? {
        let inScenes = game.scenes.actorsInScenes()
        let combat = game.combat.loop
        let seats = game.furniture.occupancies
        let actors = game.actorWorld.combatActors().map { actor in
            var flags = game.packages.runtime?.currentPackage(for: actor.key)?
                .package.general.interruptFlags
            if flags != nil, game.packages.allowsSandboxConversation(actor.key) {
                flags = (flags ?? 0) | SocialActor.conversationFlag
            }
            var social = SocialActor(
                key: actor.key,
                feet: actor.feet,
                interruptFlags: flags,
                isDead: actor.isDead,
                isInScene: inScenes.contains(actor.key),
                isInCombat: (combat?.activity(of: actor.key) ?? .notFighting) != .notFighting,
                combatTarget: combat?.combatTarget(of: actor.key)
            )
            social.heading = game.streamer.npcTransform(for: actor.key)?.placement.rotation.z ?? 0
            social.posture = Self.posture(of: seats[actor.key])
            social.fightsRanged = combat?.fightsRanged(actor.key) ?? false
            return social
        }
        return SocialFrame(
            actors: actors,
            now: sceneCast.sceneSeconds,
            isInterior: game.streamer.interiorScene != nil,
            playerInConversation: game.dialogue.conversationSpeaker != nil,
            player: game.gameSession?.walkController.feetPosition
        )
    }

    /// xEdit's furniture animation enum: 1 sit, 2 lay. A lean counts as standing.
    static let sitAnimation: UInt16 = 1
    static let layAnimation: UInt16 = 2

    static func posture(of occupancy: FurnitureOccupancy?) -> SocialPosture {
        let type = occupancy?.seat.seat.animationType
        if type == Self.sitAnimation {
            return .sitting
        }
        return type == Self.layAnimation ? .sleeping : .standing
    }

    /// Eye to the body's chest, about half a standing actor's eye height.
    public func socialCanSee(_ observer: SocialActor, _ body: SocialActor) -> Bool {
        let eye = observer.feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight)
        let chest = body.feet + SIMD3(0, 0, PlayerCapsule.standard.torsoHeight)
        return game.aiWorld.perceptionHasLineOfSight(from: eye, to: chest)
    }
}
