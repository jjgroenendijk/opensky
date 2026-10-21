// The world geometry a landed spell's defences ask about: whether a ward holder
// faces the caster, and whether a wall stands between the impact and a bystander.

import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

extension MagicWorldAdapter {
    /// Half of the ward's front arc. UESP "Skyrim:Ward": "the angle of protection is
    /// pretty generous (around 90 degrees)".
    static let wardHalfArc: Float = .pi / 4
    /// How far the wall ray starts from the impact, so the surface a projectile hit
    /// does not count as the wall.
    static let sightStartOffset: Float = 2

    func actor(_ target: ReferenceKey, faces source: ReferenceKey) -> Bool {
        guard let holder = standing(target), let caster = standing(source) else { return true }
        let toward = SIMD2(caster.feet.x - holder.feet.x, caster.feet.y - holder.feet.y)
        guard simd_length(toward) > .ulpOfOne else { return true }
        let forward = SIMD2(cosf(holder.facing), sinf(holder.facing))
        return simd_dot(simd_normalize(toward), forward) >= cosf(Self.wardHalfArc)
    }

    func point(_ point: SIMD3<Float>, canSee target: ReferenceKey) -> Bool {
        guard let actor = standing(target) else { return true }
        let centre = actor.feet + SIMD3(0, 0, actor.height / 2)
        let path = centre - point
        let distance = simd_length(path)
        guard distance > Self.sightStartOffset else { return true }
        let direction = path / distance
        let hit = game.combat.sweepProjectile(.sphere(
            center: point + direction * Self.sightStartOffset,
            radius: 0,
            direction: direction,
            maximumDistance: distance - Self.sightStartOffset
        ))
        return hit == nil
    }

    private func standing(_ key: ReferenceKey) -> StandingActor? {
        if key == .player {
            let player = game.combat.meleeAttacker
            return StandingActor(
                feet: player.feet, facing: player.facing, height: player.capsule.height
            )
        }
        guard let actor = game.actorWorld.combatActors().first(where: { $0.key == key })
        else { return nil }
        return StandingActor(
            feet: actor.feet, facing: actor.facing, height: actor.capsule.height * actor.scale
        )
    }
}

private struct StandingActor {
    let feet: SIMD3<Float>
    let facing: Float
    let height: Float
}
