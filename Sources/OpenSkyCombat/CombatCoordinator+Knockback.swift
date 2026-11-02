// A strong melee or ranged hit knocks its target back, away from the attacker, by
// `HitKnockback` (docs/engine/impulses.md#hits).

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

    /// Knocks `target` back after a hit of `damage` that found it at `health`. Only a
    /// weapon hit with a known attacker pushes, because the push needs a direction.
    @discardableResult
    func knockBack(
        _ target: ReferenceKey, damage: Float, health: (current: Float, maximum: Float),
        attacker: ReferenceKey, kind: CombatHitKind
    ) -> HitKnock? {
        guard
            kind == .melee || kind == .ranged, let impulses, let world = impulses.world,
            let from = feet(of: attacker), let to = feet(of: target)
        else { return nil }
        let settings = impulses.settings
        let roll = Float(strikeRandom.percent()) / 100
        let scale = kind == .ranged ? settings.projectileKnock.biped : 1
        guard let knock = HitKnockback.knock(
            damage: damage, health: health, roll: roll, scale: scale, settings: settings
        ) else { return nil }
        let away = SIMD3(to.x - from.x, to.y - from.y, 0)
        guard simd_length(away) > 0.001 else { return nil }
        let velocity = simd_normalize(away) * knock.speed
        guard world.knockActor(target, velocity: velocity, knockdown: knock.isKnockdown)
        else { return nil }
        impulses.record(.knock(
            target, speed: knock.speed, knockdown: knock.isKnockdown,
            cause: kind == .ranged ? .ranged : .melee
        ))
        return knock
    }

    private func feet(of key: ReferenceKey) -> SIMD3<Float>? {
        key == .player ? meleeAttacker.feet : combatActor(key: key)?.feet
    }
}
