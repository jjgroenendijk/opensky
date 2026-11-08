// The loaded actors as sources of breath and movement loops: where each stands, whether
// it is awake and moving, and its sound types (docs/engine/actor-sounds.md).

import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldState

extension ActorGraphWorldAdapter {
    func actorSoundSources() -> [ActorSoundSource] {
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
                isMoving: movers.contains(actor.key)
            )
        }
    }

    /// The sound types of the actor's own NPC_ record, the leaf of its leveled lists.
    private func sounds(of key: ReferenceKey, base: FormID) -> ActorSounds {
        guard let resolver = game.worldData?.actorValueBaselines?.resolver else { return .none }
        let templates = resolver.templates
        let roll = game.worldState.leveledRoll(of: key, base: base, with: templates.leveling)
        let cacheKey = LeveledActorRollKey(base: base, roll: roll)
        if let cached = actorSounds[cacheKey] {
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
        actorSounds[cacheKey] = sounds
        return sounds
    }
}
