import OpenSkyActorPresentation
import OpenSkyAIPackages
public import OpenSkyAudio
import OpenSkyBehavior
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `ActorGraphGraphEventsAdapter` reads from the session.
@MainActor
public protocol ActorGraphGraphEventsHost: AnyObject {
    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)?
    var actorWorld: any ActorWorldPort { get }
    var dragonFlight: any DragonFlightPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var idleWorld: any IdleWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var vehicleWorld: any VehicleWorldPort { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `ActorGraphWorldAdapter`, over its own narrow host.
public struct ActorGraphGraphEventsAdapter {
    public unowned let owner: ActorGraphWorldAdapter
    public unowned let game: any ActorGraphGraphEventsHost
}

extension ActorGraphGraphEventsAdapter {
    public func actorGraphFired(_ fired: String, from actor: ReferenceKey) {
        let name = game.idleWorld.idles.ownGraphEvent(fired, from: actor)
        game.gameSession?.animationEvents?.handle(name, from: actor)
        game.dragonFlight.handle(name, from: actor)
        game.vehicleWorld.handleBodyEvent(name, from: actor)
        game.scripts.runtime?.queueAnimationEvent(sender: actor, name: name)
        guard
            let feet = game.actorWorld.combatActor(key: actor)?.feet,
            let footsteps = game.gameSession?.footstepDirector
        else { return }
        footsteps.handleActorGraphEvents(
            [name], gait: owner.gaits[actor] ?? .walk, position: feet,
            armatures: game.actorPlayback(for: actor)?.armorAddons.footstepArmatures ?? [],
            material: owner.groundMaterials[actor]
        )
    }

    public func graphBase(of actor: ReferenceKey, base: FormID) -> ActorGraphWorldAdapter
        .GraphBase?
    {
        guard let resolver = game.worldData?.actorValueBaselines?.resolver else { return nil }
        let roll = game.worldState.leveledRoll(
            of: actor, base: base, with: resolver.templates.leveling
        )
        let key = LeveledActorRollKey(base: base, roll: roll)
        if let cached = owner.graphBases[key] {
            return cached
        }
        let identity = ActorIdentityRecords(resolver: resolver)
        let race = identity.race(ofBase: base, roll: roll).flatMap { identity.races[$0.rawValue] }
        let graphs = race?.details.behaviorGraphs
        let female = identity.isFemale(ofBase: base, roll: roll) ?? false
        let model = (female ? graphs?.female : nil) ?? graphs?.male
        let path = model.map { ActorGraphCore.projectPath(modelPath: $0.path) }
        let weight = (try? resolver.templates.rolling(roll).resolve(base: base).weight) ?? 50
        let graphBase = ActorGraphWorldAdapter.GraphBase(path: path, weight: weight)
        owner.graphBases[key] = graphBase
        return graphBase
    }

    public func actorSoundSources() -> [ActorSoundSource] {
        guard let streamer = game.streamer else { return [] }
        return game.actorWorld.combatActors().compactMap { actor in
            guard
                let base = streamer.residentActorEntry(key: actor.key)?.placedActor?.base
            else { return nil }
            let sounds = sounds(of: actor.key, base: base)
            guard !sounds.types.isEmpty else { return nil }
            let unconscious = game.worldState
                .component(ScriptedReferenceState.self, for: actor.key)?
                .flag(ScriptedStateName.unconscious) == true
            return ActorSoundSource(
                key: actor.key, position: actor.feet, sounds: sounds,
                isConscious: !actor.isDead && !unconscious,
                isMoving: owner.movers.contains(actor.key)
            )
        }
    }

    /// The sound types of the actor's own NPC_ record, the leaf of its leveled lists.
    private func sounds(of key: ReferenceKey, base: FormID) -> ActorSounds {
        guard let resolver = game.worldData?.actorValueBaselines?.resolver else { return .none }
        let templates = resolver.templates
        let roll = game.worldState.leveledRoll(of: key, base: base, with: templates.leveling)
        let cacheKey = LeveledActorRollKey(base: base, roll: roll)
        if let cached = owner.actorSounds[cacheKey] {
            return cached
        }
        let chain = (try? templates.rolling(roll).resolve(base: base).chain) ?? []
        let npc = chain.lazy.compactMap { link -> FormID? in
            if case let .npc(id) = link {
                return id
            }
            return nil
        }.first ?? base
        let sounds = ActorSounds.of(npc) { id in
            templates.actors[id.rawValue].map {
                ActorSoundRecord(
                    inheritsFrom: $0.details.inheritsSoundsFrom,
                    types: $0.details.soundTypes
                )
            }
        }
        owner.actorSounds[cacheKey] = sounds
        return sounds
    }
}
