// A melee hit knocks its target back, away from the attacker, by `HitKnockback`, and a
// strong one knocks it down (docs/engine/impulses.md#hits).

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import simd

extension CombatCoordinator {
    /// The impulse runtime the explosions share. Nil pushes nothing.
    public var impulses: ImpulseRuntime? {
        explosions.impulses
    }

    /// Knocks `target` back as a melee hit of `damage` from the player would, without
    /// the damage. Nil when the hit is too weak or the target cannot be pushed.
    @discardableResult
    public func forceKnockBack(_ target: ReferenceKey, damage: Float) -> HitKnock? {
        guard let health = world.health(of: target) else { return nil }
        return knockBack(target, damage: damage, health: health, attacker: .player, kind: .melee)
    }

    /// Knocks `target` back after a melee hit of `damage` that found it at `health`. A
    /// blocked hit, or a ranged one, pushes no actor.
    @discardableResult
    func knockBack(
        _ target: ReferenceKey, damage: Float, health: (current: Float, maximum: Float),
        attacker: ReferenceKey, kind: CombatHitKind
    ) -> HitKnock? {
        guard
            kind == .melee, meleeBlock(of: target) == nil,
            let impulses, let world = impulses.world, world.isPushable(target),
            let from = feet(of: attacker), let to = feet(of: target)
        else { return nil }
        let roll = Float(strikeRandom.percent()) / 100
        guard let knock = HitKnockback.knock(
            damage: damage, health: health, roll: roll, settings: impulses.settings
        ) else { return nil }
        let away = SIMD3(to.x - from.x, to.y - from.y, 0)
        guard simd_length(away) > 0.001 else { return nil }
        let velocity = simd_normalize(away) * knock.speed
        let pushed = knock.isKnockdown
            ? world.knockDown(
                target, from: from, magnitude: knock.speed / GameplayImpulse.havokScale
            )
            : world.knockActor(target, velocity: velocity, knockdown: false)
        guard pushed else { return nil }
        impulses.record(.knock(
            target,
            speed: knock.speed,
            knockdown: knock.isKnockdown,
            cause: .melee
        ))
        return knock
    }

    private func feet(of key: ReferenceKey) -> SIMD3<Float>? {
        key == .player ? meleeAttacker.feet : combatActor(key: key)?.feet
    }
}
