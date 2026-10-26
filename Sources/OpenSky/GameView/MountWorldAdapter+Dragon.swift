// App side of a ridden dragon's orders: the lock target in view, where the target
// stands, and the breath at it (docs/engine/dragon-flight.md#riding).

import OpenSkyActorPresentation
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import simd

extension MountWorldAdapter {
    /// How far from the view centre, in radians, an actor can be locked.
    static let lockCone: Float = 0.25
    /// The farthest a rider locks a target from, in units.
    static let lockRange: Float = 8000

    /// The living actor closest to the view centre, inside the lock cone and range.
    func lockCandidate() -> ReferenceKey? {
        guard let camera = game.gameSession?.freeFlyCamera else { return nil }
        let mount = mounts.drive?.mount
        var best: (key: ReferenceKey, angle: Float)?
        for actor in game.actorWorld.combatActors()
            where !actor.isDead && actor.key != .player && actor.key != mount
        {
            let offset = actor.feet - camera.position
            let distance = simd_length(offset)
            guard distance > 1, distance <= Self.lockRange else { continue }
            let angle = acos(min(max(simd_dot(offset / distance, camera.forward), -1), 1))
            if angle <= Self.lockCone, angle < best?.angle ?? .infinity {
                best = (actor.key, angle)
            }
        }
        return best?.key
    }

    func livingActorFeet(_ key: ReferenceKey) -> SIMD3<Float>? {
        guard let actor = game.actorWorld.combatActor(key: key), !actor.isDead else {
            return nil
        }
        return actor.feet
    }

    /// The dragon's strongest breath shout, cast at the target as a named-target spell.
    func breathe(from mount: ReferenceKey, at target: ReferenceKey) {
        guard
            let holder = game.magicWorld.actorValueHolder(for: mount),
            let spell = game.magic.npcShouts(of: holder).lazy
                .compactMap({ $0.words.last(where: { $0.spell != nil })?.spell }).first
        else { return }
        game.scripts.bridge?.castSpell(spell.key, from: mount, at: target)
    }
}
