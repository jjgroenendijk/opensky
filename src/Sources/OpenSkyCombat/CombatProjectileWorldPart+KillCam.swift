// The release check of a bow, crossbow, or spell kill cam: the facts of the player's shot,
// read from the combat world. See docs/engine/kill-cam.md#bow-and-spell-kill-cams-in-the-game.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

extension CombatProjectileWorldPart {
    /// How far off the aim line an actor may stand and still be the kill cam's target,
    /// when the aim help picked none.
    static let killCamSearchSlack: Float = 32

    func projectileKillCamAim(
        for projectile: LiveProjectile, aimTarget: ReferenceKey?
    ) -> SIMD3<Float>? {
        guard let loop = shared.loop else { return nil }
        let arrow = projectile.payload.arrow
        let spell = projectile.payload.spell
        guard arrow != nil || spell != nil else { return nil }
        let world = shared.world
        let enemies = world.residentActors().filter {
            !$0.isDead && world.hostility(of: $0.key) == .hostile
                && loop.activity(of: $0.key) != .notFighting
        }
        let origin = projectile.launchPosition
        let candidates = world.residentActors().filter { !$0.isDead && $0.key != .player }
        guard
            let target = candidates.first(where: { $0.key == aimTarget })
            ?? Self.nearestOnLine(candidates, from: origin, along: projectile.launchDirection)
        else { return nil }
        let centre = target.feet + SIMD3(0, 0, target.capsule.height * target.scale / 2)
        var facts = RangedKillCamFacts()
        facts.enemiesInCombat = enemies.count
        let health = world.health(of: target.key)
        facts.targetAlive = (health?.current ?? 0) > 0
        let damage = arrow?.damage.applied ?? spell.map { world.spellHealthDamage($0) } ?? 0
        facts.hitKills = damage > 0 && damage >= (health?.current ?? .infinity)
        // Spells and crossbows have no draw to check.
        facts.draw = arrow.flatMap { $0.handType == .crossbow ? nil : $0.damage.drawFraction }
        facts.clearLine = clearLine(from: origin, to: centre)
        facts.distance = simd_distance(origin, centre)
        facts.targetLevel = world.level(of: target.key)
        facts.playerLevel = world.level(of: .player)
        facts.playerHealthShare = world.health(of: .player).map {
            $0.maximum > 0 ? $0.current / $0.maximum : 1
        } ?? 1
        facts.undetectedSneakShot = arrow != nil
            && shared.strikes.isSneakAttack(by: .player, on: target.key)
        facts.targetIsHostileThreat = enemies.contains { $0.key == target.key }
        let roll = Float(shared.archeryRandom.percent())
        let plays = RangedKillCam.plays(facts, roll: roll)
        var check = ProjectileReadout.KillCamCheck(
            target: target.key, enemiesInCombat: facts.enemiesInCombat,
            targetAlive: facts.targetAlive, hitKills: facts.hitKills, damage: damage,
            clearLine: facts.clearLine, distance: facts.distance
        )
        check.chance = RangedKillCam.chance(facts)
        check.roll = roll
        check.plays = plays
        shared.lastKillCamCheck = check
        guard plays else { return nil }
        shared.pendingCommands.append(.rangedKillCam(projectile: projectile.id, target: target.key))
        return centre
    }

    private func clearLine(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Bool {
        let offset = end - start
        let length = simd_length(offset)
        guard length > 1 else { return true }
        return shared.world.sweep(.sphere(
            center: start, radius: 1, direction: offset / length, maximumDistance: length
        )) == nil
    }

    /// The actor nearest the shooter whose body the aim line passes within reach of.
    private static func nearestOnLine(
        _ actors: [CombatActorObservation], from origin: SIMD3<Float>, along direction: SIMD3<Float>
    ) -> CombatActorObservation? {
        guard simd_length_squared(direction) > 0 else { return nil }
        let unit = simd_normalize(direction)
        return actors.compactMap { actor -> (CombatActorObservation, Float)? in
            let centre = actor.feet + SIMD3(0, 0, actor.capsule.height * actor.scale / 2)
            let along = simd_dot(centre - origin, unit)
            guard along > 0 else { return nil }
            let miss = simd_distance(origin + unit * along, centre)
            let reach = actor.capsule.radius * actor.scale + killCamSearchSlack
            return miss <= reach ? (actor, along) : nil
        }
        .min { $0.1 < $1.1 }?.0
    }
}
