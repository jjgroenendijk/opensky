// Which actors a blast reaches through its walls, and the health it takes off them.
// A satellite of `ExplosionRuntime`. See docs/engine/explosions.md#damage.

import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

extension ExplosionRuntime {
    /// The actors inside the radius that no wall shields, the shooter among them. A wall
    /// shields nobody when the blast ignores line of sight.
    func reach(
        _ spec: ExplosionSpec, at position: SIMD3<Float>, origin: ExplosionOrigin
    ) -> (reached: [MeleeTarget], shielded: [ReferenceKey]) {
        guard spec.damage > 0 || spec.enchantment != nil, let world else { return ([], []) }
        let start = ExplosionSight.start(center: position, direction: origin.direction)
        var reached: [MeleeTarget] = []
        var shielded: [ReferenceKey] = []
        for target in world.explosionTargets() {
            let share = ExplosionFalloff.fraction(
                radius: spec.radius, distance: Self.distance(position, target)
            )
            guard share > 0 else { continue }
            if !spec.ignoresLineOfSight {
                let centre = target.feet + SIMD3(0, 0, target.capsule.height / 2)
                let end = target.key == .player ? world.explosionViewer() ?? centre : centre
                let hit = world.explosionObstruction(from: start, to: end)
                if ExplosionSight.blocks(hitDistance: hit, direction: origin.direction) {
                    if target.key != origin.shooter {
                        shielded.append(target.key)
                    }
                    continue
                }
            }
            reached.append(target)
        }
        return (reached, shielded)
    }

    /// Health off each reached actor but the shooter, scaled by the shooter's skill.
    func damage(
        _ spec: ExplosionSpec, reached: [MeleeTarget], at position: SIMD3<Float>,
        origin: ExplosionOrigin
    ) -> [ReferenceKey: Float] {
        guard spec.damage > 0, let world else { return [:] }
        let scale = ExplosionSkill.scale(skill: origin.skill, isPlayer: origin.shooter == .player)
        var damaged: [ReferenceKey: Float] = [:]
        for target in reached where target.key != origin.shooter {
            let amount = ExplosionFalloff.damage(
                spec.damage, radius: spec.radius, distance: Self.distance(position, target)
            ) * scale
            guard amount > 0 else { continue }
            if world.applyExplosionDamage(amount, to: target.key) {
                damaged[target.key] = amount
                if let owner = origin.shooter {
                    world.noteExplosionSound(owner: owner, level: spec.soundLevel, at: target.feet)
                }
            }
        }
        return damaged
    }
}
